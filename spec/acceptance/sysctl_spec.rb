require 'spec_helper_acceptance'

test_name 'Augeasproviders Sysctl'

describe 'Sysctl Tests' do
  hosts.each do |host|
    context 'file based updates' do
      let(:manifest) do
        <<-EOM
          sysctl { 'fs.nr_open':
            value => '100000',
            apply => false
          }
        EOM
      end

      # Using puppet_apply as a helper
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      it 'has applied successfuly in the sysctl config but not live' do
        result = on(host, 'sysctl -n fs.nr_open').stdout.strip
        expect(result).not_to eql('100000')

        on(host, 'sysctl -p', accept_all_exit_codes: true)
        result = on(host, 'sysctl -n fs.nr_open').stdout.strip
        expect(result).to eql('100000')
      end
    end

    context 'full updates' do
      let(:manifest) do
        <<-EOM
          sysctl { 'fs.nr_open':
            value => '100001'
          }
        EOM
      end

      # Using puppet_apply as a helper
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      it 'applies successfuly in the config and live' do
        result = on(host, 'sysctl -n fs.nr_open').stdout.strip
        expect(result).to eql('100001')
      end

      context 'when given an invalid key' do
        let(:manifest) do
          <<-EOM
            sysctl { 'fs.this_cannot_exist':
              value => 'I like bread'
            }
          EOM
        end

        it 'fails to apply to the system' do
          apply_manifest_on(host, manifest, expect_failures: true)
        end
      end

      context 'when silent' do
        let(:manifest) do
          <<-EOM
            sysctl { 'fs.nr_open':
              value  => '100002',
              silent => true
            }
          EOM
        end

        # Using puppet_apply as a helper
        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end
      end

      context 'when silent and given a key that does not exist' do
        let(:manifest) do
          <<-EOM
            sysctl { 'fs.this_cannot_exist':
              value  => 'I like bread',
              silent => true
            }
          EOM
        end

        # Using puppet_apply as a helper
        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end
      end

      context 'when only applying to the running system' do
        let(:manifest) do
          <<-EOM
            sysctl { 'kernel.pty.max':
              value   => 4097,
              apply   => true,
              persist => false
            }
          EOM
        end

        # Using puppet_apply as a helper
        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end

        it 'is not in /etc/sysctl.conf' do
          on(host, 'grep kernel.pty.max /etc/sysctl.conf', acceptable_exit_codes: [1])
        end
      end

      context 'when only applying to the filesystem' do
        let(:manifest) do
          <<-EOM
            sysctl { 'kernel.pty.max':
              comment => 'just a test',
              value   => 4098,
              apply   => false,
              persist => true
            }
          EOM
        end

        # Using puppet_apply as a helper
        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end

        it 'is in /etc/sysctl.conf' do
          on(host, 'grep "kernel.pty.max = 4098" /etc/sysctl.conf')
        end

        it 'is not changed on the running system' do
          result = on(host, 'sysctl -n kernel.pty.max').stdout.strip
          expect(result).to eql('4097')
        end
      end

      context 'when deleting an entry' do
        let(:manifest) do
          <<-EOM
            sysctl { 'kernel.pty.max':
              ensure  => absent
            }
          EOM
        end

        # Using puppet_apply as a helper
        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end

        it 'is not in /etc/sysctl.conf' do
          on(host, 'grep "kernel.pty.max" /etc/sysctl.conf', acceptable_exit_codes: [1])
        end

        it 'is not changed on the running system' do
          result = on(host, 'sysctl -n kernel.pty.max').stdout.strip
          expect(result).to eql('4097')
        end
      end
    end
  end
end
