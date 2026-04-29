# Alternative Augeas-based provider for sysctl type
#
# Copyright (c) 2012 Dominic Cleal
# Licensed under the Apache License, Version 2.0

raise('Missing augeasproviders_core dependency') if Puppet::Type.type(:augeasprovider).nil?

Puppet::Type.type(:sysctl).provide(:augeas, parent: Puppet::Type.type(:augeasprovider).provider(:default)) do
  desc 'Uses Augeas API to update sysctl settings'

  default_file do
    if Facter.value(:os)['name'] == 'Debian' && Facter.value(:os)['release']['major'].to_i >= 13
      '/etc/sysctl.d/99-puppet.conf'
    else
      '/etc/sysctl.conf'
    end
  end

  lens { 'Sysctl.lns' }

  optional_commands sysctl: 'sysctl'

  resource_path do |resource|
    "$target/#{resource[:name]}"
  end

  def self.sysctl_set(key, value, silent = false)
    if Facter.value(:kernel) == :openbsd
      sysctl("#{key}=#{value}")
    else
      sysctl('-w', %(#{key}=#{value}))
    end
  rescue Puppet::ExecutionFailure => e
    raise e unless silent

    debug("augeasprovider_sysctl ignoring failed attempt to set #{key} due to :silent mode")
  end

  def self.sysctl_get(key)
    sysctl('-n', key).chomp
  end

  # Set or remove a managed comment for a sysctl entry. Used by both
  # cleanup_duplicates and the comment= property setter.
  def self.set_managed_comment(aug, name, comment_text)
    cmtnode = "$target/#comment[following-sibling::*[1][self::#{name}]][. =~ regexp('#{Regexp.escape(name)}:.*')]"
    if comment_text.empty?
      aug.rm(cmtnode)
    else
      aug.insert("$target/#{name}", '#comment', true) if aug.match(cmtnode).empty?
      aug.set("$target/#comment[following-sibling::*[1][self::#{name}]]",
              "#{name}: #{comment_text}")
    end
  end

  confine feature: :augeas

  def self.collect_augeas_resources(res, entries, target = '/etc/sysctl.conf', resources)
    resources ||= []

    augopen(res) do |aug|
      entries.each do |entry|
        next if resources.find { |x| x[:name] == entry }

        value = aug.get("$target/#{entry}")

        next unless value

        resource = {
          name: entry,
          ensure: :present,
          persist: :true,
          value: value,
          target: target
        }

        # Only match comments immediately before the entry and prefixed with
        # the sysctl name
        cmtnode = aug.match("$target/#comment[following-sibling::*[1][self::#{entry}]]")
        unless cmtnode.empty?
          comment = aug.get(cmtnode[0])
          resource[:comment] = comment.sub(%r{^#{resource[:name]}:\s*}, '') if comment.match(%r{#{resource[:name]}:})
        end

        resources << resource
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

      sysctl_args = if Facter.value(:kernel) == 'OpenBSD'
                      # OpenBSD doesn't support -e
                      ['']
                    elsif Facter.value(:kernel) == 'FreeBSD'
                      ['-ieW']
                    else
                      ['-e']
                    end

      # Split this into chunks so that we don't exceed command line limits
      reference_resource_titles.each_slice(30) do |resource_title_slice|
        sysctl_args << resource_title_slice

        sysctl_output += sysctl(sysctl_args.flatten)
      end
    else
      targets = ['/etc/sysctl.d/*.conf', '/etc/sysctl.conf']
      targets = [target] if target

      Dir.glob(targets).reverse.each do |config_file|
        tmp_res = Puppet::Resource.new('sysctl', 'ignored')
        tmp_res[:target] = config_file

        entries = []
        augopen(tmp_res) do |aug|
          entries = aug.match('$target/*').
                    delete_if { |x| x.match?(%r{#comment}) }.
                    map { |x| x.split('/').last }
        end

        collect_augeas_resources(
          tmp_res,
          entries,
          config_file,
          resources
        )
      end

      sysctl_args = ['-a']

      sysctl_args = ['-aeW'] if Facter.value(:kernel) == 'FreeBSD'

      sysctl_output = sysctl(sysctl_args)
    end

    sep = '='
    sysctl_output.each_line do |line|
      line = line.force_encoding('US-ASCII').scrub('')
      value = line.split(sep)

      key = value.shift.strip

      value = value.join(sep).strip

      existing_index = resources.index { |x| x[:name] == key }

      if existing_index
        resources[existing_index][:apply] = :true
      else
        newres = {
          name: key,
          ensure: :present,
          value: value,
          apply: :true,
          persist: :false
        }

        newres[:target] = target if target

        resources << newres
      end
    end

    resources.map { |x| x = new(x) }
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
    return unless resource[:persist] == :true
    raise Puppet::Error, "Error: `#{resource[:name]}` is not a valid sysctl key" if !valid_resource?(resource[:name]) && (resource[:silent] == :false)

    # the value to pass to augeas can come either from the 'value' or the
    # 'val' type parameter.
    value = resource[:value] || resource[:val]

    augopen! do |aug|
      # Prefer to create the node next to a commented out entry
      commented = aug.match("$target/#comment[.=~regexp('#{resource[:name]}([^a-z.].*)?')]")
      aug.insert(commented.first, resource[:name], false) unless commented.empty?
      aug.set(resource_path, value)
      setvars(aug)
    end
  end

  # Remove duplicate entries for this resource's key. Returns true if
  # the entry exists on disk after cleanup (used by flush to decide
  # whether create is needed).
  #
  # Property setters (value=, comment=) run on the shared Augeas
  # handler BEFORE flush. With duplicates, aug.get returns nil and
  # aug.set is a no-op, so those changes are silently lost. After
  # removing duplicates, this method re-applies value and comment
  # so the tree is correct before augsave! runs.
  #
  def cleanup_duplicates
    exists = false

    augopen! do |aug|
      entries = aug.match("$target/#{resource[:name]}")
      exists = !entries.empty?
      next if entries.length <= 1

      # Build an ordered list of all children so we can find the
      # specific comment preceding each duplicate entry.
      all_children = aug.match('$target/*')

      # Remove duplicates in reverse order to preserve path indices
      # for entries earlier in the list.
      entries[1..].reverse_each do |entry_path|
        idx = all_children.index(entry_path)
        if idx && idx > 0
          prev = all_children[idx - 1]
          if prev.include?('#comment')
            comment_val = aug.get(prev)
            aug.rm(prev) if comment_val&.match?(%r{^#{Regexp.escape(resource[:name])}:})
          end
        end
        aug.rm(entry_path)
      end

      # The earlier comment= setter ran against an ambiguous
      # `$target/#{name}` path. `aug.insert` failed silently, but the
      # follow-up `aug.set` on a predicate path with no match still
      # created a stray managed #comment node at the end of the tree.
      # Remove it before re-applying so we don't duplicate the comment.
      trailing = aug.match('$target/*').last
      if trailing&.include?('#comment') &&
         aug.get(trailing)&.match?(%r{^#{Regexp.escape(resource[:name])}:})
        aug.rm(trailing)
      end

      # Re-apply value (ambiguous aug.set was a no-op before cleanup)
      value = resource[:value] || resource[:val]
      aug.set("$target/#{resource[:name]}", value) if value

      # Re-apply comment (property setter was a no-op due to ambiguity)
      self.class.set_managed_comment(aug, resource[:name], resource[:comment]) if resource[:comment]
    end

    exists
  end

  def valid_resource?(name)
    @property_hash.is_a?(Hash) && @property_hash[:name] == name
  end

  def exists?
    # If in silent mode, short circuit the process on an invalid key
    #
    # This only matters when creating entries since invalid missing entries
    # might be used to clean up /etc/sysctl.conf
    if resource[:ensure] != :absent && !valid_resource?(resource[:name])
      raise Puppet::Error, "Error: `#{resource[:name]}` is not a valid sysctl key" unless resource[:silent] == :true

      debug("augeasproviders_sysctl: `#{resource[:name]}` is not a valid sysctl key")
      return true

    end

    if @property_hash[:ensure] == :present
      # Short circuit this if there's nothing to do
      return false if (resource[:ensure] == :absent) && (@property_hash[:persist] == :false)

      true

    else
      super
    end
  end

  define_aug_method!(:destroy) do |aug, resource|
    loop do
      break if aug.match("$target/#{resource[:name]}").empty?

      aug.rm("$target/#comment[following-sibling::*[1][self::#{resource[:name]}]][. =~ regexp('#{Regexp.escape(resource[:name])}:.*')]")
      aug.rm("$target/#{resource[:name]}")
    end
  end

  def live_value
    return self.class.sysctl_get(resource[:name]) unless resource[:silent] == :true

    debug("augeasproviders_sysctl not setting live value for #{resource[:name]} due to :silent mode")
    return resource[:value] if resource[:value]

    resource[:val]
  end

  attr_aug_accessor(:value, label: :resource)

  alias_method :val, :value
  alias_method :val=, :value=

  define_aug_method(:comment) do |aug, resource|
    comment = aug.get("$target/#comment[following-sibling::*[1][self::#{resource[:name]}]][. =~ regexp('#{resource[:name]}:.*')]")
    comment.sub!(%r{^#{resource[:name]}:\s*}, '') if comment
    comment || ''
  end

  define_aug_method!(:comment=) do |aug, resource, value|
    set_managed_comment(aug, resource[:name], value)
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
        # Remove duplicates first. With duplicate entries, aug.get returns
        # nil, so prefetch marks the entry as persist: :false even though
        # it exists on disk. cleanup_duplicates returns whether the entry
        # exists after cleanup, avoiding a separate augeas session.
        on_disk = cleanup_duplicates

        create if @property_hash[:persist] == :false && !on_disk

        super
      end
    end
  end
end
