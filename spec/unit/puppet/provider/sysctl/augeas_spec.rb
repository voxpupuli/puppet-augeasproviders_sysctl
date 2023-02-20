#!/usr/bin/env rspec

require 'spec_helper'

provider_class = Puppet::Type.type(:sysctl).provider(:augeas)

describe provider_class do
  before :each do
    allow(FileTest).to receive(:exist?).and_return(false)
    allow(FileTest).to receive(:exist?).with('/etc/sysctl.conf').and_return(true)

    # TODO: Is there a better way?
    #provider_class.instance_variable_set(:@resource_cache, nil)

    # This needs to be a list of all sysctls used in the tests so that prefetch
    # works and the provider doesn't fail on an invalid key.
    allow(provider_class).to receive(:sysctl).with(['-a']).and_return([
      'net.ipv4.ip_forward = 1',
      'net.bridge.bridge-nf-call-iptables = 0',
      'kernel.sem = 100   13000 11  1200',
      'kernel.sysrq = 0',
      ''
    ].join("\n"))
  end

  before(:all) { @tmpdir = Dir.mktmpdir }
  after(:all) { FileUtils.remove_entry_secure @tmpdir }

  context "with no existing file" do
    let(:target) { File.join(@tmpdir, "new_file") }

    before :each do
      expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=0")
      expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1')
      expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').at_least(:once).and_return('1')
      expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=1")
    end

    it "should create simple new entry" do
      apply!(Puppet::Type.type(:sysctl).new(
        :name     => "net.ipv4.ip_forward",
        :value    => "1",
        :target   => target,
        :provider => "augeas"
      ))

      augparse(target, "Sysctl.lns", '
        { "net.ipv4.ip_forward" = "1" }
      ')
    end
  end

  context "with empty file" do
    let(:tmptarget) { aug_fixture("empty") }
    let(:target) { tmptarget.path }

    before :each do
      expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=0")
      expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1')
      expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').at_least(:once).and_return('1')
      expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=1")
    end

    it "should create simple new entry" do
      apply!(Puppet::Type.type(:sysctl).new(
        :name     => "net.ipv4.ip_forward",
        :value    => "1",
        :target   => target,
        :provider => "augeas"
      ))

      augparse(target, "Sysctl.lns", '
        { "net.ipv4.ip_forward" = "1" }
      ')
    end

    it "should create an entry using the val parameter instead of value" do
      apply!(Puppet::Type.type(:sysctl).new(
        :name     => "net.ipv4.ip_forward",
        :val      => "1",
        :target   => target,
        :provider => "augeas"
      ))

      augparse(target, "Sysctl.lns", '
        { "net.ipv4.ip_forward" = "1" }
      ')
    end

    it "should create new entry with comment" do
      apply!(Puppet::Type.type(:sysctl).new(
        :name     => "net.ipv4.ip_forward",
        :value    => "1",
        :comment  => "test",
        :target   => target,
        :provider => "augeas"
      ))

      augparse(target, "Sysctl.lns", '
        { "#comment" = "net.ipv4.ip_forward: test" }
        { "net.ipv4.ip_forward" = "1" }
      ')
    end
  end

  context "with full file" do
    let(:tmptarget) { aug_fixture("full") }
    let(:target) { tmptarget.path }

    it "should list instances" do
      allow(provider_class).to receive(:target).and_return(target)

      inst = provider_class.instances.map { |p|
        {
          :name => p.get(:name),
          :ensure => p.get(:ensure),
          :value => p.get(:value),
          :comment => p.get(:comment),
        }
      }

      expect(inst.size).to eq(9)
      expect(inst[0]).to eq({:name=>"net.ipv4.ip_forward", :ensure=>:present, :value=>"0", :comment=>:absent})
      expect(inst[1]).to eq({:name=>"net.ipv4.conf.default.rp_filter", :ensure=>:present, :value=>"1", :comment=>:absent})
      expect(inst[2]).to eq({:name=>"net.ipv4.conf.default.accept_source_route", :ensure=>:present, :value=>"0", :comment=>"Do not accept source routing"})
      expect(inst[3]).to eq({:name=>"kernel.sysrq", :ensure=>:present, :value=>"0", :comment=>"controls the System Request debugging functionality of the kernel"})
    end

    it "should create new entry next to commented out entry" do
      expect(provider_class).to receive(:sysctl).with(['-e', 'net.bridge.bridge-nf-call-iptables']).and_return("net.bridge.bridge-nf-call-iptables=0")
      expect(provider_class).to receive(:sysctl).with('-w', 'net.bridge.bridge-nf-call-iptables=1')
      expect(provider_class).to receive(:sysctl).with('-n', 'net.bridge.bridge-nf-call-iptables').at_least(:once).and_return('1')
      expect(provider_class).to receive(:sysctl).with(['-e', 'net.bridge.bridge-nf-call-iptables']).and_return("net.bridge.bridge-nf-call-iptables=1")

      apply!(Puppet::Type.type(:sysctl).new(
        :name     => "net.bridge.bridge-nf-call-iptables",
        :value    => "1",
        :target   => target,
        :provider => "augeas"
      ))

      augparse_filter(target, "Sysctl.lns", '*[preceding-sibling::#comment[.="Disable netfilter on bridges."]]', '
        { "net.bridge.bridge-nf-call-ip6tables" = "0" }
        { "#comment" = "net.bridge.bridge-nf-call-iptables = 0" }
        { "net.bridge.bridge-nf-call-iptables" = "1" }
        { "net.bridge.bridge-nf-call-arptables" = "0" }
      ')
    end

    it "should equate multi-part values with tabs in" do


      expect(provider_class).to receive(:sysctl).with(['-e', 'kernel.sem']).and_return("kernel.sem=123\t123\t123\t123")
      expect(provider_class).to receive(:sysctl).with('-n', 'kernel.sem').at_least(:once).and_return("150\t12000\t12\t1000")
      expect(provider_class).to receive(:sysctl).with('-w', 'kernel.sem=150   12000 12  1000')
      expect(provider_class).to receive(:sysctl).with(['-e', 'kernel.sem']).and_return("kernel.sem=150\t12000\t12\t1000")

      apply!(Puppet::Type.type(:sysctl).new(
        :name     => "kernel.sem",
        :value    => "150   12000 12  1000",
        :apply    => true,
        :target   => target,
        :provider => "augeas"
      ))

      augparse_filter(target, "Sysctl.lns", "kernel.sem", '
        { "kernel.sem" = "150   12000 12  1000" }
      ')
    end

    # Validated that it *does* delete the entries but somethign about prefetch
    # isn't playing well with the way the tests are loaded and, unfortunately,
    # I can't short circuit it.
    xit "should delete entries" do
      apply!(Puppet::Type.type(:sysctl).new(
        :name     => "kernel.sysrq",
        :ensure   => "absent",
        :target   => target,
        :provider => "augeas"
      ))

      aug_open(target, "Sysctl.lns") do |aug|
        expect(aug.match("kernel.sysrq")).to eq([])
        expect(aug.match("#comment[. =~ regexp('kernel.sysrq:.*')]")).to eq([])
      end
    end

    context 'when system and config values are set to different values' do
      it "should update value with augeas and sysctl" do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=3")
        expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').at_least(:once).and_return('3', '1')
        expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1')
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=1")

        apply!(Puppet::Type.type(:sysctl).new(
          :name     => "net.ipv4.ip_forward",
          :value    => "1",
          :apply    => true,
          :target   => target,
          :provider => "augeas"
        ))

        augparse_filter(target, "Sysctl.lns", "net.ipv4.ip_forward", '
          { "net.ipv4.ip_forward" = "1" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed configuration value from '0' to '1' and live value from '3' to '1'")
      end

      it "should update value with augeas only" do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("")
        expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').never
        expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1').never
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("")

        apply!(Puppet::Type.type(:sysctl).new(
          :name     => "net.ipv4.ip_forward",
          :value    => "1",
          :apply    => false,
          :target   => target,
          :provider => "augeas"
        ))

        augparse_filter(target, "Sysctl.lns", "net.ipv4.ip_forward", '
          { "net.ipv4.ip_forward" = "1" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed configuration value from '0' to '1'")
      end
    end

    context 'when system and config values are set to the same value' do
      it "should update value with augeas and sysctl" do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=0")
        expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').at_least(:once).and_return('0', '1')
        expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1')
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=1")

        apply!(Puppet::Type.type(:sysctl).new(
          :name     => "net.ipv4.ip_forward",
          :value    => "1",
          :apply    => true,
          :target   => target,
          :provider => "augeas"
        ))

        augparse_filter(target, "Sysctl.lns", "net.ipv4.ip_forward", '
          { "net.ipv4.ip_forward" = "1" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed configuration value from '0' to '1' and live value from '0' to '1'")
      end

      it "should update value with augeas only" do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("")
        expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').never
        expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1').never
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("")

        apply!(Puppet::Type.type(:sysctl).new(
          :name     => "net.ipv4.ip_forward",
          :value    => "1",
          :apply    => false,
          :target   => target,
          :provider => "augeas"
        ))

        augparse_filter(target, "Sysctl.lns", "net.ipv4.ip_forward", '
          { "net.ipv4.ip_forward" = "1" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed configuration value from '0' to '1'")
      end
    end

    context 'when only system value is set to target value' do
      it "should update value with augeas only" do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=1")
        expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').twice.and_return('1')
        # Values not in sync, system update forced anyway
        expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1').once.and_return('1')
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=1")

        apply!(Puppet::Type.type(:sysctl).new(
          :name     => "net.ipv4.ip_forward",
          :value    => "1",
          :apply    => true,
          :target   => target,
          :provider => "augeas"
        ))

        augparse_filter(target, "Sysctl.lns", "net.ipv4.ip_forward", '
          { "net.ipv4.ip_forward" = "1" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed configuration value from '0' to '1'")
      end

      it "should update value with augeas only and never run sysctl" do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("")
        expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').never
        expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1').never
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("")

        apply!(Puppet::Type.type(:sysctl).new(
          :name     => "net.ipv4.ip_forward",
          :value    => "1",
          :apply    => false,
          :target   => target,
          :provider => "augeas"
        ))

        augparse_filter(target, "Sysctl.lns", "net.ipv4.ip_forward", '
          { "net.ipv4.ip_forward" = "1" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed configuration value from '0' to '1'")
      end
    end

    context 'when only config value is set to target value' do
      it "should update value with sysctl only" do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=1")
        expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').twice.and_return('1', '0')
        # Values not in sync, system update forced anyway
        expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=0').once.and_return('0')
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=0")

        apply!(Puppet::Type.type(:sysctl).new(
          :name     => "net.ipv4.ip_forward",
          :value    => "0",
          :apply    => true,
          :target   => target,
          :provider => "augeas"
        ))

        augparse_filter(target, "Sysctl.lns", "net.ipv4.ip_forward", '
          { "net.ipv4.ip_forward" = "0" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed live value from '1' to '0'")
      end

      it "should not update value with sysctl" do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=0")
        expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').never
        expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=0').never
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=0")

        apply!(Puppet::Type.type(:sysctl).new(
          :name     => "net.ipv4.ip_forward",
          :value    => "0",
          :apply    => false,
          :target   => target,
          :provider => "augeas"
        ))

        augparse_filter(target, "Sysctl.lns", "net.ipv4.ip_forward", '
          { "net.ipv4.ip_forward" = "0" }
        ')

        expect(@logs.first).to be_nil
      end
    end

    context "when updating comment" do
      it "should change comment" do
        expect(provider_class).to receive(:sysctl).with(['-e', 'kernel.sysrq']).twice.and_return("kernel.sysrq=enables the SysRq feature")

        apply!(Puppet::Type.type(:sysctl).new(
          :name     => "kernel.sysrq",
          :comment  => "enables the SysRq feature",
          :target   => target,
          :provider => "augeas"
        ))

        aug_open(target, "Sysctl.lns") do |aug|
          expect(aug.match("#comment[. = 'SysRq setting']")).not_to eq([])
          expect(aug.match("#comment[. = 'kernel.sysrq: enables the SysRq feature']")).not_to eq([])
        end
      end

      it "should remove comment" do
        expect(provider_class).to receive(:sysctl).with(['-e', 'kernel.sysrq']).twice.and_return("kernel.sysrq=enables the SysRq feature")

        apply!(Puppet::Type.type(:sysctl).new(
          :name     => "kernel.sysrq",
          :comment  => "",
          :target   => target,
          :provider => "augeas"
        ))

        aug_open(target, "Sysctl.lns") do |aug|
          expect(aug.match("#comment[. =~ regexp('kernel.sysrq:.*')]")).to eq([])
          expect(aug.match("#comment[. = 'SysRq setting']")).not_to eq([])
        end
      end
    end

    context 'when not persisting' do
      it "should not persist the value on disk" do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=0")
        expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').twice.and_return('0', '1')
        expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1').once
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return("net.ipv4.ip_forward=1")

        apply!(Puppet::Type.type(:sysctl).new(
          :name     => "net.ipv4.ip_forward",
          :value    => "1",
          :apply    => true,
          :target   => target,
          :provider => "augeas",
          :persist  => false
        ))

        augparse_filter(target, "Sysctl.lns", "net.ipv4.ip_forward", '
          { "net.ipv4.ip_forward" = "0" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed live value from '0' to '1'")
      end

      it "should not add comment to the value on disk" do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).twice.and_return("net.ipv4.ip_forward=1")

        apply!(Puppet::Type.type(:sysctl).new(
          :name     => "net.ipv4.ip_forward",
          :target   => target,
          :provider => "augeas",
          :persist  => false,
          :comment  => "This is a test"
        ))

        aug_open(target, "Sysctl.lns") do |aug|
          aug.get("net.ipv4.ip_forward").should eq "0"
          aug.get("#comment[4]").should eq "Controls IP packet forwarding"
        end

        expect(@logs.first).to be_nil
      end
    end
  end

  context "with small file" do
    let(:tmptarget) { aug_fixture("small") }
    let(:target) { tmptarget.path }

    describe "when updating comment" do
      it "should add comment" do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).twice.and_return("net.ipv4.ip_forward=1")

        apply!(Puppet::Type.type(:sysctl).new(
          :name     => "net.ipv4.ip_forward",
          :comment  => "test comment",
          :target   => target,
          :provider => "augeas"
        ))

        augparse(target, "Sysctl.lns", '
          { "#comment" = "Kernel sysctl configuration file" }
          { }
          { "#comment" = "For binary values, 0 is disabled, 1 is enabled.  See sysctl(8) and" }
          { "#comment" = "sysctl.conf(5) for more details." }
          { }
          { "#comment" = "Controls IP packet forwarding" }
          { "#comment" = "net.ipv4.ip_forward: test comment" }
          { "net.ipv4.ip_forward" = "0" }
          { }
        ')
      end
    end
  end

  context "with broken file" do
    let(:tmptarget) { aug_fixture("broken") }
    let(:target) { tmptarget.path }

    it "should fail to load" do
      expect {
        apply(Puppet::Type.type(:sysctl).new(
          :name     => "net.ipv4.ip_forward",
          :value    => "1",
          :target   => target,
          :provider => "augeas"
        ))
      }.to raise_error(/target/)
    end
  end
end
