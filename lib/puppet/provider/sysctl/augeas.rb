# Alternative Augeas-based provider for sysctl type
#
# Copyright (c) 2012 Dominic Cleal
# Licensed under the Apache License, Version 2.0

raise("Missing augeasproviders_core dependency") if Puppet::Type.type(:augeasprovider).nil?
Puppet::Type.type(:sysctl).provide(:augeas, :parent => Puppet::Type.type(:augeasprovider).provider(:default)) do
  desc "Uses Augeas API to update sysctl settings"

  default_file { '/etc/sysctl.conf' }

  lens { 'Sysctl.lns' }

  optional_commands :sysctl => 'sysctl'

  resource_path do |resource|
    "$target/#{resource[:name]}"
  end

  def self.sysctl_set(key, value, silent=false)
    begin
      if Facter.value(:kernel) == :openbsd
        sysctl("#{key}=#{value}")
      else
        sysctl('-w', %Q{#{key}=#{value}})
      end
    rescue Puppet::ExecutionFailure => e
      if silent
        debug("augeasprovider_sysctl ignoring failed attempt to set #{key} due to :silent mode")
      else
        raise e
      end
    end
  end

  def self.sysctl_get(key)
    sysctl('-n', key).chomp
  end

  confine :feature => :augeas

  def self.collect_augeas_resources(res, entries, target='/etc/sysctl.conf', resources)
    resources ||= []

    augopen(res) do |aug|
      entries.each do |entry|
        next if resources.find{|x| x[:name] == entry}

        value = aug.get("$target/#{entry}")

        if value
          resource = {
            :name    => entry,
            :ensure  => :present,
            :persist => :true,
            :value   => value,
            :target  => target
          }

          # Only match comments immediately before the entry and prefixed with
          # the sysctl name
          cmtnode = aug.match("$target/#comment[following-sibling::*[1][self::#{entry}]]")
          unless cmtnode.empty?
            comment = aug.get(cmtnode[0])
            if comment.match(/#{resource[:name]}:/)
              resource[:comment] = comment.sub(/^#{resource[:name]}:\s*/, "")
            end
          end

          resources << resource
        end
      end
    end

    resources
  end

  def self.instances(reference_resources = nil)
    resources = []
    sysctl_output = ''

    if reference_resources
      reference_resource_titles = reference_resources.map { |_ref_name, ref_obj| ref_obj.title }
      resource_dup = reference_resources.first.last.dup

      collect_augeas_resources(
        resource_dup,
        reference_resource_titles,
        resource_dup[:target],
        resources
      )

      if Facter.value(:kernel) == 'OpenBSD'
        # OpenBSD doesn't support -e
        sysctl_args = ['']
      elsif Facter.value(:kernel) == 'FreeBSD'
        sysctl_args = ['-ieW']
      else
        sysctl_args = ['-e']
      end

      # Split this into chunks so that we don't exceed command line limits
      reference_resource_titles.each_slice(30) do |resource_title_slice|
        sysctl_args << resource_title_slice

        sysctl_output += sysctl(sysctl_args.flatten)
      end
    else
      Dir.glob(['/etc/sysctl.d/*.conf', '/etc/sysctl.conf']).reverse.each do |config_file|
        tmp_res = Puppet::Resource.new('sysctl', 'ignored')
        tmp_res[:target] = config_file

        entries = []
        augopen(tmp_res) do |aug|
          entries = aug.match("$target/*")
            .delete_if{|x| x.match?(/#comment/)}
            .map{|x| x.split('/').last}
        end

        collect_augeas_resources(
          tmp_res,
          entries,
          config_file,
          resources
        )
      end

      sysctl_args = ['-a']

      if Facter.value(:kernel) == 'FreeBSD'
        sysctl_args = ['-aeW']
      end

      sysctl_output = sysctl(sysctl_args)
    end

    sep = '='
    sysctl_output.each_line do |line|
      line = line.force_encoding("US-ASCII").scrub("")
      value = line.split(sep)

      key = value.shift.strip

      value = value.join(sep).strip

      existing_index = resources.index{ |x| x[:name] == key }

      if existing_index
        resources[existing_index][:apply] = :true
      else
        resources << {
          :name    => key,
          :ensure  => :present,
          :value   => value,
          :apply   => :true,
          :persist => :false
        }
      end
    end

    resources.map{|x| x = new(x)}
  end

  def self.prefetch(resources)
    # We need to pass a reference resource so that the proper target is in
    # scope.
    instances(resources).each do |prov|
      if resource = resources[prov.name]
        resource.provider = prov
      end
    end
  end

  def create
    if resource[:persist] == :true
      if !valid_resource?(resource[:name]) && (resource[:silent] == :false)
        raise Puppet::Error, "Error: `#{resource[:name]}` is not a valid sysctl key"
      end

      # the value to pass to augeas can come either from the 'value' or the
      # 'val' type parameter.
      value = resource[:value] || resource[:val]

      augopen! do |aug|
        # Prefer to create the node next to a commented out entry
        commented = aug.match("$target/#comment[.=~regexp('#{resource[:name]}([^a-z\.].*)?')]")
        aug.insert(commented.first, resource[:name], false) unless commented.empty?
        aug.set(resource_path, value)
        setvars(aug)
      end
    end
  end

  def valid_resource?(name)
    @property_hash.is_a?(Hash) && @property_hash[:name] == name
  end

  def exists?
    # If in silent mode, short circuit the process on an invalid key
    #
    # This only matters when creating entries since invalid missing entries
    # might be used to clean up /etc/sysctl.conf
    if resource[:ensure] != :absent
      if !valid_resource?(resource[:name])
        if resource[:silent] == :true
          debug("augeasproviders_sysctl: `#{resource[:name]}` is not a valid sysctl key")
          return true
        else
          raise Puppet::Error, "Error: `#{resource[:name]}` is not a valid sysctl key"
        end
      end
    end

    if @property_hash[:ensure] == :present
      # Short circuit this if there's nothing to do
      if (resource[:ensure] == :absent) && (@property_hash[:persist] == :false)
        return false
      else
        return true
      end
    else
      super
    end
  end


  define_aug_method!(:destroy) do |aug, resource|
    aug.rm("$target/#comment[following-sibling::*[1][self::#{resource[:name]}]][. =~ regexp('#{resource[:name]}:.*')]")
    aug.rm('$resource')
  end

  def live_value
    if resource[:silent] == :true
      debug("augeasproviders_sysctl not setting live value for #{resource[:name]} due to :silent mode")
      if resource[:value]
        return resource[:value]
      else
        return resource[:val]
      end
    else
      return self.class.sysctl_get(resource[:name])
    end
  end

  attr_aug_accessor(:value, :label => :resource)

  alias_method :val, :value
  alias_method :val=, :value=

  define_aug_method(:comment) do |aug, resource|
    comment = aug.get("$target/#comment[following-sibling::*[1][self::#{resource[:name]}]][. =~ regexp('#{resource[:name]}:.*')]")
    comment.sub!(/^#{resource[:name]}:\s*/, "") if comment
    comment || ""
  end

  define_aug_method!(:comment=) do |aug, resource, value|
    cmtnode = "$target/#comment[following-sibling::*[1][self::#{resource[:name]}]][. =~ regexp('#{resource[:name]}:.*')]"
    if value.empty?
      aug.rm(cmtnode)
    else
      if aug.match(cmtnode).empty?
        aug.insert('$resource', "#comment", true)
      end
      aug.set("$target/#comment[following-sibling::*[1][self::#{resource[:name]}]]",
              "#{resource[:name]}: #{resource[:comment]}")
    end
  end

  def flush
    if resource[:ensure] == :absent
      super
    else
      if resource[:apply] == :true
        value = resource[:value] || resource[:val]
        if value
          silent = (resource[:silent] == :true)
          self.class.sysctl_set(resource[:name], value, silent)
        end
      end

      # Ensures that we only save to disk when we're supposed to
      if resource[:persist] == :true
        # Create the entry on disk if it's not already there
        if @property_hash[:persist] == :false
          create
        end

        super
      end
    end
  end
end
