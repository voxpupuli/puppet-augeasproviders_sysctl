require 'spec_helper_acceptance'

test_name 'Augeasproviders Sysctl'

describe 'Sysctl Tests' do
  hosts.each do |host|
    context "on #{host}" do
      let(:sysctl_conf) do
        if fact_on(host, 'os.name') == 'Debian' && (fact_on(host, 'os.release.major') || '0').to_i >= 13
          '/etc/sysctl.d/99-puppet.conf'
        else
          '/etc/sysctl.conf'
        end
      end
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
          apply_manifest_on(host, manifest, { catch_changes: true })
        end

        it 'has applied successfuly in the sysctl config but not live' do
          result = on(host, 'sysctl -n fs.nr_open').stdout.strip
          expect(result).not_to eql('100000')

          on(host, "sysctl -p #{sysctl_conf}", accept_all_exit_codes: true)
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
          apply_manifest_on(host, manifest, { catch_changes: true })
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
            apply_manifest_on(host, manifest, { catch_changes: true })
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
            apply_manifest_on(host, manifest, { catch_changes: true })
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
            apply_manifest_on(host, manifest, { catch_changes: true })
          end

          it 'is not in default config file' do
            expect(file_contents_on(host, sysctl_conf)).not_to match(%r{kernel\.pty\.max})
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
            apply_manifest_on(host, manifest, { catch_changes: true })
          end

          it 'is in default config file' do
            expect(file_contents_on(host, sysctl_conf)).to match(%r{kernel\.pty\.max = 4098})
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
            apply_manifest_on(host, manifest, { catch_changes: true })
          end

          it 'is not in default config file' do
            expect(file_contents_on(host, sysctl_conf)).not_to match(%r{kernel\.pty\.max})
          end

          it 'is not changed on the running system' do
            result = on(host, 'sysctl -n kernel.pty.max').stdout.strip
            expect(result).to eql('4097')
          end
        end

        context 'when using a target file' do
          let(:manifest) do
            <<-EOM
              if $facts['os']['family'] == 'RedHat' and versioncmp($facts['os']['release']['major'], '9') >= 0 {
                package { 'systemd-udev':
                  ensure => 'installed',
                }
                Package['systemd-udev'] -> Sysctl <| |>
              }
              sysctl { 'fs.nr_open':
                value  => '100001',
                target => '/etc/sysctl.d/20-fs.conf'
              }

              sysctl { 'fs.inotify.max_user_watches':
                value  => '8193',
                target => '/etc/sysctl.d/20-fs.conf'
              }
            EOM
          end

          it 'works with no errors' do
            apply_manifest_on(host, manifest, catch_failures: true)
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, { catch_changes: true })
          end

          it 'has correct file contents' do
            expect(file_contents_on(host, sysctl_conf)).to match(%r{fs\.nr_open = 100002})
            expect(file_contents_on(host, sysctl_conf)).not_to match(%r{fs\.inotify\.max_user_watches})
            expect(file_contents_on(host, '/etc/sysctl.d/20-fs.conf')).to match(%r{fs\.nr_open = 100001})
            expect(file_contents_on(host, '/etc/sysctl.d/20-fs.conf')).to match(%r{fs\.inotify\.max_user_watches = 8193})
          end

          context 'when deleting an entry' do
            let(:manifest) do
              <<-EOM
                sysctl { 'fs.inotify.max_user_watches':
                  ensure => absent,
                  target => '/etc/sysctl.d/20-fs.conf'
                }
              EOM
            end

            it 'works with no errors' do
              apply_manifest_on(host, manifest, catch_failures: true)
            end

            it 'is idempotent' do
              apply_manifest_on(host, manifest, { catch_changes: true })
            end

            it 'has been removed from the system' do
              expect(file_contents_on(host, '/etc/sysctl.d/20-fs.conf')).not_to match(%r{fs\.inotify\.max_user_watches})
            end
          end
        end

        context 'with no value' do
          let(:manifest) do
            "sysctl { 'vm.swappiness': }"
          end

          it 'works with no errors' do
            apply_manifest_on(host, manifest, catch_failures: true)
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, catch_changes: true)
          end
        end

        context 'when setting multiple values' do
          let(:manifest) do
            <<-EOS
              sysctl { 'vm.swappiness': value => '60' }
              sysctl { 'net.ipv4.ip_forward': value => '0' }
            EOS
          end

          it 'works with no errors' do
            apply_manifest_on(host, manifest, catch_failures: true)
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, catch_changes: true)
          end
        end

        context 'when removing multiple values' do
          let(:manifest_one) do
            <<-EOS
              sysctl { 'vm.swappiness': value => '60' }
              sysctl { 'net.ipv4.ip_forward': value => '0' }
            EOS
          end
          let(:manifest_two) do
            <<-EOS
              sysctl { 'vm.swappiness': ensure => 'absent' }
              sysctl { 'net.ipv4.ip_forward': ensure => 'absent' }
            EOS
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest_one, catch_failures: true)
            apply_manifest_on(host, manifest_two, catch_failures: true)
            apply_manifest_on(host, manifest_two, catch_changes: true)
          end
        end

        context 'when managing multiple files' do
          let(:manifest) do
            <<-EOS
              sysctl{'net.ipv6.conf.all.disable_ipv6': ensure => present, value => 1, target => '/etc/sysctl.d/99-disable-ipv6.conf' }
              sysctl{'net.ipv4.tcp_syncookies':         ensure => present, value => 2, target => '/etc/sysctl.d/99-ddos-abwehr.conf'}
            EOS
          end

          it 'works with no errors' do
            apply_manifest_on(host, manifest, catch_failures: true)
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, catch_changes: true)
          end

          describe 'removing one of two settings' do
            let(:manifest_one) do
              <<-EOS
                sysctl{'net.ipv6.conf.all.disable_ipv6': ensure => present, value => 1, target => '/etc/sysctl.d/99-disable-ipv6.conf' }
                sysctl{'net.ipv4.tcp_syncookies':         ensure => present, value => 2, target => '/etc/sysctl.d/99-ddos-abwehr.conf'}
              EOS
            end
            let(:manifest_two) do
              <<-EOS
                sysctl{'net.ipv6.conf.all.disable_ipv6': ensure => present, value => 1, target => '/etc/sysctl.d/99-disable-ipv6.conf' }
                sysctl{'net.ipv4.tcp_syncookies':         ensure => absent, target => '/etc/sysctl.d/99-ddos-abwehr.conf'}
              EOS
            end

            it 'is idempotent' do
              apply_manifest_on(host, manifest_one, catch_failures: true)
              apply_manifest_on(host, manifest_two, catch_failures: true)
              apply_manifest_on(host, manifest_two, catch_changes: true)
            end
          end
        end
      end
    end
  end
end
