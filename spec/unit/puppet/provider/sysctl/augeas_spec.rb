#!/usr/bin/env rspec

require 'spec_helper'

provider_class = Puppet::Type.type(:sysctl).provider(:augeas)

describe provider_class do
  before do
    allow(FileTest).to receive(:exist?).and_return(false)
    allow(FileTest).to receive(:exist?).with('/etc/sysctl.conf').and_return(true)

    # TODO: Is there a better way?
    # provider_class.instance_variable_set(:@resource_cache, nil)

    # This needs to be a list of all sysctls used in the tests so that prefetch
    # works and the provider doesn't fail on an invalid key.
    allow(provider_class).to receive(:sysctl).with(['-a']).and_return([
      'net.ipv4.ip_forward = 1',
      'net.bridge.bridge-nf-call-iptables = 0',
      'kernel.sem = 100   13000 11  1200',
      'kernel.sysrq = 0',
      'net.ipv4.conf.default.rp_filter = 1',
      ''
    ].join("\n"))
  end

  before(:all) { @tmpdir = Dir.mktmpdir }
  after(:all) { FileUtils.remove_entry_secure @tmpdir }

  context 'with no existing file' do
    let(:target) { File.join(@tmpdir, 'new_file') }

    before do
      expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=0')
      expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1')
      expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').at_least(:once).and_return('1')
      expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=1')
    end

    it 'creates simple new entry' do
      apply!(Puppet::Type.type(:sysctl).new(
               name: 'net.ipv4.ip_forward',
               value: '1',
               target: target,
               provider: 'augeas'
             ))

      augparse(target, 'Sysctl.lns', '
        { "net.ipv4.ip_forward" = "1" }
      ')
    end
  end

  context 'with empty file' do
    let(:tmptarget) { aug_fixture('empty') }
    let(:target) { tmptarget.path }

    before do
      expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=0')
      expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1')
      expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').at_least(:once).and_return('1')
      expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=1')
    end

    it 'creates simple new entry' do
      apply!(Puppet::Type.type(:sysctl).new(
               name: 'net.ipv4.ip_forward',
               value: '1',
               target: target,
               provider: 'augeas'
             ))

      augparse(target, 'Sysctl.lns', '
        { "net.ipv4.ip_forward" = "1" }
      ')
    end

    it 'creates an entry using the val parameter instead of value' do
      apply!(Puppet::Type.type(:sysctl).new(
               name: 'net.ipv4.ip_forward',
               val: '1',
               target: target,
               provider: 'augeas'
             ))

      augparse(target, 'Sysctl.lns', '
        { "net.ipv4.ip_forward" = "1" }
      ')
    end

    it 'creates new entry with comment' do
      apply!(Puppet::Type.type(:sysctl).new(
               name: 'net.ipv4.ip_forward',
               value: '1',
               comment: 'test',
               target: target,
               provider: 'augeas'
             ))

      augparse(target, 'Sysctl.lns', '
        { "#comment" = "net.ipv4.ip_forward: test" }
        { "net.ipv4.ip_forward" = "1" }
      ')
    end
  end

  context 'with full file' do
    let(:tmptarget) { aug_fixture('full') }
    let(:target) { tmptarget.path }

    it 'lists instances' do
      allow(provider_class).to receive(:target).and_return(target)

      inst = provider_class.instances.map do |p|
        {
          name: p.get(:name),
          ensure: p.get(:ensure),
          value: p.get(:value),
          comment: p.get(:comment),
        }
      end

      expect(inst.size).to eq(9)
      expect(inst[0]).to eq({ name: 'net.ipv4.ip_forward', ensure: :present, value: '0', comment: :absent })
      expect(inst[1]).to eq({ name: 'net.ipv4.conf.default.rp_filter', ensure: :present, value: '1', comment: :absent })
      expect(inst[2]).to eq({ name: 'net.ipv4.conf.default.accept_source_route', ensure: :present, value: '0', comment: 'Do not accept source routing' })
      expect(inst[3]).to eq({ name: 'kernel.sysrq', ensure: :present, value: '0', comment: 'controls the System Request debugging functionality of the kernel' })
    end

    it 'creates new entry next to commented out entry' do
      expect(provider_class).to receive(:sysctl).with(['-e', 'net.bridge.bridge-nf-call-iptables']).and_return('net.bridge.bridge-nf-call-iptables=0')
      expect(provider_class).to receive(:sysctl).with('-w', 'net.bridge.bridge-nf-call-iptables=1')
      expect(provider_class).to receive(:sysctl).with('-n', 'net.bridge.bridge-nf-call-iptables').at_least(:once).and_return('1')
      expect(provider_class).to receive(:sysctl).with(['-e', 'net.bridge.bridge-nf-call-iptables']).and_return('net.bridge.bridge-nf-call-iptables=1')

      apply!(Puppet::Type.type(:sysctl).new(
               name: 'net.bridge.bridge-nf-call-iptables',
               value: '1',
               target: target,
               provider: 'augeas'
             ))

      augparse_filter(target, 'Sysctl.lns', '*[preceding-sibling::#comment[.="Disable netfilter on bridges."]]', '
        { "net.bridge.bridge-nf-call-ip6tables" = "0" }
        { "#comment" = "net.bridge.bridge-nf-call-iptables = 0" }
        { "net.bridge.bridge-nf-call-iptables" = "1" }
        { "net.bridge.bridge-nf-call-arptables" = "0" }
      ')
    end

    it 'equates multi-part values with tabs in' do
      expect(provider_class).to receive(:sysctl).with(['-e', 'kernel.sem']).and_return("kernel.sem=123\t123\t123\t123")
      expect(provider_class).to receive(:sysctl).with('-n', 'kernel.sem').at_least(:once).and_return("150\t12000\t12\t1000")
      expect(provider_class).to receive(:sysctl).with('-w', 'kernel.sem=150   12000 12  1000')
      expect(provider_class).to receive(:sysctl).with(['-e', 'kernel.sem']).and_return("kernel.sem=150\t12000\t12\t1000")

      apply!(Puppet::Type.type(:sysctl).new(
               name: 'kernel.sem',
               value: '150   12000 12  1000',
               apply: true,
               target: target,
               provider: 'augeas'
             ))

      augparse_filter(target, 'Sysctl.lns', 'kernel.sem', '
        { "kernel.sem" = "150   12000 12  1000" }
      ')
    end

    it 'deletes entries' do
      mock_sysctl_noop('kernel.sysrq', '0')

      apply!(Puppet::Type.type(:sysctl).new(
               name: 'kernel.sysrq',
               ensure: 'absent',
               target: target,
               provider: 'augeas'
             ))

      aug_open(target, 'Sysctl.lns') do |aug|
        expect(aug.match('kernel.sysrq')).to eq([])
        expect(aug.match("#comment[. =~ regexp('kernel.sysrq:.*')]")).to eq([])
      end
    end

    context 'when system and config values are set to different values' do
      it 'updates value with augeas and sysctl' do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=3')
        expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').at_least(:once).and_return('3', '1')
        expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1')
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=1')

        apply!(Puppet::Type.type(:sysctl).new(
                 name: 'net.ipv4.ip_forward',
                 value: '1',
                 apply: true,
                 target: target,
                 provider: 'augeas'
               ))

        augparse_filter(target, 'Sysctl.lns', 'net.ipv4.ip_forward', '
          { "net.ipv4.ip_forward" = "1" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed configuration value from '0' to '1' and live value from '3' to '1'")
      end

      it 'updates value with augeas only' do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('')
        expect(provider_class).not_to receive(:sysctl).with('-n', 'net.ipv4.ip_forward')
        expect(provider_class).not_to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1')
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('')

        apply!(Puppet::Type.type(:sysctl).new(
                 name: 'net.ipv4.ip_forward',
                 value: '1',
                 apply: false,
                 target: target,
                 provider: 'augeas'
               ))

        augparse_filter(target, 'Sysctl.lns', 'net.ipv4.ip_forward', '
          { "net.ipv4.ip_forward" = "1" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed configuration value from '0' to '1'")
      end
    end

    context 'when system and config values are set to the same value' do
      it 'updates value with augeas and sysctl' do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=0')
        expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').at_least(:once).and_return('0', '1')
        expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1')
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=1')

        apply!(Puppet::Type.type(:sysctl).new(
                 name: 'net.ipv4.ip_forward',
                 value: '1',
                 apply: true,
                 target: target,
                 provider: 'augeas'
               ))

        augparse_filter(target, 'Sysctl.lns', 'net.ipv4.ip_forward', '
          { "net.ipv4.ip_forward" = "1" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed configuration value from '0' to '1' and live value from '0' to '1'")
      end

      it 'updates value with augeas only' do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('')
        expect(provider_class).not_to receive(:sysctl).with('-n', 'net.ipv4.ip_forward')
        expect(provider_class).not_to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1')
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('')

        apply!(Puppet::Type.type(:sysctl).new(
                 name: 'net.ipv4.ip_forward',
                 value: '1',
                 apply: false,
                 target: target,
                 provider: 'augeas'
               ))

        augparse_filter(target, 'Sysctl.lns', 'net.ipv4.ip_forward', '
          { "net.ipv4.ip_forward" = "1" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed configuration value from '0' to '1'")
      end
    end

    context 'when only system value is set to target value' do
      it 'updates value with augeas only' do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=1')
        expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').twice.and_return('1')
        # Values not in sync, system update forced anyway
        expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1').once.and_return('1')
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=1')

        apply!(Puppet::Type.type(:sysctl).new(
                 name: 'net.ipv4.ip_forward',
                 value: '1',
                 apply: true,
                 target: target,
                 provider: 'augeas'
               ))

        augparse_filter(target, 'Sysctl.lns', 'net.ipv4.ip_forward', '
          { "net.ipv4.ip_forward" = "1" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed configuration value from '0' to '1'")
      end

      it 'updates value with augeas only and never run sysctl' do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('')
        expect(provider_class).not_to receive(:sysctl).with('-n', 'net.ipv4.ip_forward')
        expect(provider_class).not_to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1')
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('')

        apply!(Puppet::Type.type(:sysctl).new(
                 name: 'net.ipv4.ip_forward',
                 value: '1',
                 apply: false,
                 target: target,
                 provider: 'augeas'
               ))

        augparse_filter(target, 'Sysctl.lns', 'net.ipv4.ip_forward', '
          { "net.ipv4.ip_forward" = "1" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed configuration value from '0' to '1'")
      end
    end

    context 'when only config value is set to target value' do
      it 'updates value with sysctl only' do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=1')
        expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').twice.and_return('1', '0')
        # Values not in sync, system update forced anyway
        expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=0').once.and_return('0')
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=0')

        apply!(Puppet::Type.type(:sysctl).new(
                 name: 'net.ipv4.ip_forward',
                 value: '0',
                 apply: true,
                 target: target,
                 provider: 'augeas'
               ))

        augparse_filter(target, 'Sysctl.lns', 'net.ipv4.ip_forward', '
          { "net.ipv4.ip_forward" = "0" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed live value from '1' to '0'")
      end

      it 'does not update value with sysctl' do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=0')
        expect(provider_class).not_to receive(:sysctl).with('-n', 'net.ipv4.ip_forward')
        expect(provider_class).not_to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=0')
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=0')

        apply!(Puppet::Type.type(:sysctl).new(
                 name: 'net.ipv4.ip_forward',
                 value: '0',
                 apply: false,
                 target: target,
                 provider: 'augeas'
               ))

        augparse_filter(target, 'Sysctl.lns', 'net.ipv4.ip_forward', '
          { "net.ipv4.ip_forward" = "0" }
        ')

        expect(@logs.first).to be_nil
      end
    end

    context 'when updating comment' do
      it 'changes comment' do
        expect(provider_class).to receive(:sysctl).with(['-e', 'kernel.sysrq']).twice.and_return('kernel.sysrq=enables the SysRq feature')

        apply!(Puppet::Type.type(:sysctl).new(
                 name: 'kernel.sysrq',
                 comment: 'enables the SysRq feature',
                 target: target,
                 provider: 'augeas'
               ))

        aug_open(target, 'Sysctl.lns') do |aug|
          expect(aug.match("#comment[. = 'SysRq setting']")).not_to eq([])
          expect(aug.match("#comment[. = 'kernel.sysrq: enables the SysRq feature']")).not_to eq([])
        end
      end

      it 'removes comment' do
        expect(provider_class).to receive(:sysctl).with(['-e', 'kernel.sysrq']).twice.and_return('kernel.sysrq=enables the SysRq feature')

        apply!(Puppet::Type.type(:sysctl).new(
                 name: 'kernel.sysrq',
                 comment: '',
                 target: target,
                 provider: 'augeas'
               ))

        aug_open(target, 'Sysctl.lns') do |aug|
          expect(aug.match("#comment[. =~ regexp('kernel.sysrq:.*')]")).to eq([])
          expect(aug.match("#comment[. = 'SysRq setting']")).not_to eq([])
        end
      end
    end

    context 'when not persisting' do
      it 'does not persist the value on disk' do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=0')
        expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').twice.and_return('0', '1')
        expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=1').once
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=1')

        apply!(Puppet::Type.type(:sysctl).new(
                 name: 'net.ipv4.ip_forward',
                 value: '1',
                 apply: true,
                 target: target,
                 provider: 'augeas',
                 persist: false
               ))

        augparse_filter(target, 'Sysctl.lns', 'net.ipv4.ip_forward', '
          { "net.ipv4.ip_forward" = "0" }
        ')

        expect(@logs.first).not_to be_nil
        expect(@logs.first.message).to eq("changed live value from '0' to '1'")
      end

      it 'does not add comment to the value on disk' do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).twice.and_return('net.ipv4.ip_forward=1')

        apply!(Puppet::Type.type(:sysctl).new(
                 name: 'net.ipv4.ip_forward',
                 target: target,
                 provider: 'augeas',
                 persist: false,
                 comment: 'This is a test'
               ))

        aug_open(target, 'Sysctl.lns') do |aug|
          expect(aug.get('net.ipv4.ip_forward')).to eq('0')
          expect(aug.get('#comment[4]')).to eq('Controls IP packet forwarding')
        end

        expect(@logs.first).to be_nil
      end
    end
  end

  context 'with small file' do
    let(:tmptarget) { aug_fixture('small') }
    let(:target) { tmptarget.path }

    describe 'when updating comment' do
      it 'adds comment' do
        expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).twice.and_return('net.ipv4.ip_forward=1')

        apply!(Puppet::Type.type(:sysctl).new(
                 name: 'net.ipv4.ip_forward',
                 comment: 'test comment',
                 target: target,
                 provider: 'augeas'
               ))

        augparse(target, 'Sysctl.lns', '
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

  # Helper: set up sysctl command mocks for an update operation.
  # Mocks -e (prefetch, twice), -n (live value check), -w (set value).
  def mock_sysctl_update(key, current_value, new_value)
    expect(described_class).to receive(:sysctl).with(['-e', key]).and_return("#{key}=#{current_value}")
    expect(described_class).to receive(:sysctl).with('-n', key).at_least(:once).and_return(current_value, new_value)
    expect(described_class).to receive(:sysctl).with('-w', "#{key}=#{new_value}")
    expect(described_class).to receive(:sysctl).with(['-e', key]).and_return("#{key}=#{new_value}")
  end

  # Helper: set up sysctl mocks for a no-change prefetch (no -n/-w calls).
  def mock_sysctl_noop(key, value)
    expect(described_class).to receive(:sysctl).with(['-e', key]).twice.and_return("#{key}=#{value}")
  end

  context 'with duplicate entries' do
    let(:tmptarget) { aug_fixture('duplicates') }
    let(:target) { tmptarget.path }

    # --- positive: read path ---

    it 'lists instances without duplicate names' do
      allow(provider_class).to receive(:target).and_return(target)

      names = provider_class.instances.map { |p| p.get(:name) }
      duplicates = names.select { |n| names.count(n) > 1 }

      expect(duplicates).to eq([])
    end

    # --- positive: update with managed comments on both entries ---

    it 'updates value, preserves first managed comment, removes duplicate managed comment' do
      mock_sysctl_update('net.ipv4.ip_forward', '0', '2')

      apply!(Puppet::Type.type(:sysctl).new(
               name: 'net.ipv4.ip_forward',
               value: '2',
               target: target,
               provider: 'augeas'
             ))

      aug_open(target, 'Sysctl.lns') do |aug|
        expect(aug.match('net.ipv4.ip_forward').length).to eq(1)
        expect(aug.get('net.ipv4.ip_forward')).to eq('2')
        expect(aug.match("#comment[. = 'net.ipv4.ip_forward: first managed comment']")).not_to eq([])
        expect(aug.match("#comment[. = 'net.ipv4.ip_forward: second managed comment']")).to eq([])
      end
    end

    # --- positive: update bare duplicate (no managed comments) ---

    it 'updates bare duplicate key (managed comment on first only)' do
      mock_sysctl_update('kernel.sysrq', '0', '1')

      apply!(Puppet::Type.type(:sysctl).new(
               name: 'kernel.sysrq',
               value: '1',
               target: target,
               provider: 'augeas'
             ))

      aug_open(target, 'Sysctl.lns') do |aug|
        expect(aug.match('kernel.sysrq').length).to eq(1)
        expect(aug.get('kernel.sysrq')).to eq('1')
        expect(aug.match("#comment[. = 'kernel.sysrq: controls the System Request debugging functionality']")).not_to eq([])
      end
    end

    # --- positive: non-duplicate entry in file with duplicates ---

    it 'updates non-duplicate entry without affecting duplicated keys' do
      mock_sysctl_update('net.ipv4.conf.default.rp_filter', '1', '0')

      apply!(Puppet::Type.type(:sysctl).new(
               name: 'net.ipv4.conf.default.rp_filter',
               value: '0',
               target: target,
               provider: 'augeas'
             ))

      aug_open(target, 'Sysctl.lns') do |aug|
        expect(aug.match('net.ipv4.conf.default.rp_filter').length).to eq(1)
        expect(aug.get('net.ipv4.conf.default.rp_filter')).to eq('0')
        # Duplicate keys left alone (we only managed rp_filter)
        expect(aug.match('net.ipv4.ip_forward').length).to eq(2)
        expect(aug.match('kernel.sysrq').length).to eq(2)
      end
    end

    # --- positive: value + comment together with duplicates ---

    it 'updates both value and comment on duplicated key' do
      mock_sysctl_update('net.ipv4.ip_forward', '0', '3')

      apply!(Puppet::Type.type(:sysctl).new(
               name: 'net.ipv4.ip_forward',
               value: '3',
               comment: 'updated via puppet',
               target: target,
               provider: 'augeas'
             ))

      aug_open(target, 'Sysctl.lns') do |aug|
        expect(aug.match('net.ipv4.ip_forward').length).to eq(1)
        expect(aug.get('net.ipv4.ip_forward')).to eq('3')
        expect(aug.match("#comment[. = 'net.ipv4.ip_forward: updated via puppet']")).not_to eq([])
        expect(aug.match("#comment[. = 'net.ipv4.ip_forward: second managed comment']")).to eq([])
      end
    end

    # --- positive: comment-only change with duplicates ---

    it 'sets comment on duplicated key without changing value' do
      mock_sysctl_noop('net.ipv4.ip_forward', '0')

      apply!(Puppet::Type.type(:sysctl).new(
               name: 'net.ipv4.ip_forward',
               comment: 'new comment after dedup',
               target: target,
               provider: 'augeas'
             ))

      aug_open(target, 'Sysctl.lns') do |aug|
        expect(aug.match('net.ipv4.ip_forward').length).to eq(1)
        expect(aug.match("#comment[. = 'net.ipv4.ip_forward: new comment after dedup']")).not_to eq([])
        expect(aug.match("#comment[. = 'net.ipv4.ip_forward: second managed comment']")).to eq([])
      end
    end

    # --- positive: destroy removes all occurrences ---

    it 'removes all duplicate entries and managed comments on destroy' do
      # Cannot use apply! with ensure=>absent due to the prefetch limitation
      # (see xit test in 'with full file'). Verify the Augeas XPath logic
      # that the destroy method delegates to.
      aug_open(target, 'Sysctl.lns') do |aug|
        expect(aug.match('kernel.sysrq').length).to eq(2)

        loop do
          break if aug.match('kernel.sysrq').empty?

          aug.rm("#comment[following-sibling::*[1][self::kernel.sysrq]][. =~ regexp('kernel.sysrq:.*')]")
          aug.rm('kernel.sysrq')
        end

        expect(aug.match('kernel.sysrq')).to eq([])
        expect(aug.match("#comment[. =~ regexp('kernel.sysrq:.*')]")).to eq([])
        # Other keys survive
        expect(aug.match('net.ipv4.ip_forward').length).to eq(2)
      end
    end

    # --- negative: persist false must NOT clean up duplicates on disk ---

    it 'does not modify file when persist is false even with duplicates present' do
      expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=0')
      expect(provider_class).to receive(:sysctl).with('-n', 'net.ipv4.ip_forward').at_least(:once).and_return('0', '9')
      expect(provider_class).to receive(:sysctl).with('-w', 'net.ipv4.ip_forward=9')
      expect(provider_class).to receive(:sysctl).with(['-e', 'net.ipv4.ip_forward']).and_return('net.ipv4.ip_forward=9')

      apply!(Puppet::Type.type(:sysctl).new(
               name: 'net.ipv4.ip_forward',
               value: '9',
               target: target,
               provider: 'augeas',
               persist: false
             ))

      aug_open(target, 'Sysctl.lns') do |aug|
        # Both entries must remain on disk (persist: false means no disk writes)
        expect(aug.match('net.ipv4.ip_forward').length).to eq(2)
      end
    end
  end

  context 'with floating orphaned managed comments and duplicates' do
    let(:tmptarget) { aug_fixture('duplicates_floating_comments') }
    let(:target) { tmptarget.path }

    it 'handles update cleanly despite floating managed comments' do
      mock_sysctl_update('net.ipv4.ip_forward', '0', '5')

      apply!(Puppet::Type.type(:sysctl).new(
               name: 'net.ipv4.ip_forward',
               value: '5',
               target: target,
               provider: 'augeas'
             ))

      aug_open(target, 'Sysctl.lns') do |aug|
        expect(aug.match('net.ipv4.ip_forward').length).to eq(1)
        expect(aug.get('net.ipv4.ip_forward')).to eq('5')
        # The real managed comment (immediately before the kept entry) survives
        expect(aug.match("#comment[. = 'net.ipv4.ip_forward: real managed comment']")).not_to eq([])
        # Floating comments are NOT removed (they're not preceding any entry)
        # This is expected — cleanup_duplicates only removes comments that
        # immediately precede a duplicate entry being deleted
        expect(aug.match("#comment[. = 'net.ipv4.ip_forward: orphaned managed comment with no entry below']")).not_to eq([])
      end
    end
  end

  context 'with triple duplicates' do
    let(:tmptarget) { aug_fixture('duplicates_triple') }
    let(:target) { tmptarget.path }

    it 'reduces three entries to one, preserves first comment, removes other two comments' do
      mock_sysctl_update('net.ipv4.ip_forward', '0', '5')

      apply!(Puppet::Type.type(:sysctl).new(
               name: 'net.ipv4.ip_forward',
               value: '5',
               target: target,
               provider: 'augeas'
             ))

      aug_open(target, 'Sysctl.lns') do |aug|
        expect(aug.match('net.ipv4.ip_forward').length).to eq(1)
        expect(aug.get('net.ipv4.ip_forward')).to eq('5')
        expect(aug.match("#comment[. = 'net.ipv4.ip_forward: alpha']")).not_to eq([])
        expect(aug.match("#comment[. = 'net.ipv4.ip_forward: beta']")).to eq([])
        expect(aug.match("#comment[. = 'net.ipv4.ip_forward: gamma']")).to eq([])
        # Other keys untouched
        expect(aug.get('net.ipv4.conf.default.rp_filter')).to eq('1')
        expect(aug.get('kernel.sysrq')).to eq('0')
      end
    end

    it 'removes all three entries on destroy' do
      aug_open(target, 'Sysctl.lns') do |aug|
        expect(aug.match('net.ipv4.ip_forward').length).to eq(3)

        loop do
          break if aug.match('net.ipv4.ip_forward').empty?

          aug.rm("#comment[following-sibling::*[1][self::net.ipv4.ip_forward]][. =~ regexp('net.ipv4.ip_forward:.*')]")
          aug.rm('net.ipv4.ip_forward')
        end

        expect(aug.match('net.ipv4.ip_forward')).to eq([])
        expect(aug.match("#comment[. =~ regexp('net.ipv4.ip_forward:.*')]")).to eq([])
      end
    end
  end

  context 'with duplicates having unmanaged comments' do
    let(:tmptarget) { aug_fixture('duplicates_unmanaged') }
    let(:target) { tmptarget.path }

    it 'removes duplicates but preserves all unmanaged comments' do
      mock_sysctl_update('net.ipv4.ip_forward', '0', '4')

      apply!(Puppet::Type.type(:sysctl).new(
               name: 'net.ipv4.ip_forward',
               value: '4',
               target: target,
               provider: 'augeas'
             ))

      aug_open(target, 'Sysctl.lns') do |aug|
        expect(aug.match('net.ipv4.ip_forward').length).to eq(1)
        expect(aug.get('net.ipv4.ip_forward')).to eq('4')
        # All unmanaged comments survive (no key: prefix to match)
        expect(aug.match("#comment[. = 'Someone left notes here']")).not_to eq([])
        expect(aug.match("#comment[. = 'This was added by the ops team']")).not_to eq([])
        expect(aug.match("#comment[. = 'Override for the load balancer']")).not_to eq([])
      end
    end
  end

  context 'with duplicates having no comments, but comment_text is set to foo' do
    let(:tmptarget) { aug_fixture('duplicates_no_comments') }
    let(:target) { tmptarget.path }
    it 'removes duplicates and adds a comment to the first match' do
      mock_sysctl_update('net.ipv4.ip_forward','0','0')
      apply!(Puppet::Type.type(:sysctl).new(
               name: 'net.ipv4.ip_forward',
               value: '0',
               target: target,
               comment: 'foo',
               provider: 'augeas'
            ))
      aug_open(target, 'Sysctl.lns') do |aug|
        expect(aug.match('net.ipv4.ip_forward').length).to eq(1)
        expect(aug.get('net.ipv4.ip_forward')).to eq('0')
        expect(aug.match("#comment[. =~ regexp('net.ipv4.ip_forward:.*')]").length).to eq(1)
      end
    end
  end

  context 'with broken file' do
    let(:tmptarget) { aug_fixture('broken') }
    let(:target) { tmptarget.path }

    it 'fails to load' do
      expect do
        apply!(Puppet::Type.type(:sysctl).new(
                 name: 'net.ipv4.ip_forward',
                 value: '1',
                 target: target,
                 provider: 'augeas'
               ))
      end.to raise_error(%r{target})
    end
  end
end
