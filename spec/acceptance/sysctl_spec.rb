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
      end

      context 'with values in files' do
        let(:manifest) do
          <<-EOM
            sysctl { 'fs.nr_open':
              value => '100000',
              target => '/etc/sysctl.d/10-fs.conf'
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
          expect(file_contents_on(host, '/etc/sysctl.d/10-fs.conf')).to match(%r{fs\.nr_open = 100000})
        end

        context 'when changing value' do
          let(:manifest) do
            <<-EOM
              sysctl { 'fs.nr_open':
                value => '100001',
                target => '/etc/sysctl.d/10-fs.conf'
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
            expect(file_contents_on(host, '/etc/sysctl.d/10-fs.conf')).to match(%r{fs\.nr_open = 100001})
          end
        end
      end

      context 'with values in separate files' do
        context 'when changing value' do
          it 'applies twice with no errors' do
            # Workaround for https://github.com/voxpupuli/puppet-augeasproviders_sysctl/issues/89
            pp = <<-EOS
            sysctl { 'kernel.sched_autogroup_enabled':
              ensure  => present,
              value   => '0',
              target  => '/etc/sysctl.d/98-sched_autogroup_enabled.conf',
              comment => 'Disable sched autogroup',
            }
            EOS
            apply_manifest(pp, catch_failures: true)

            pp2 = <<-EOS
            sysctl { 'kernel.sched_autogroup_enabled':
              ensure  => present,
              value   => '1',
              target  => '/etc/sysctl.d/98-sched_autogroup_enabled.conf',
              comment => 'Enable sched autogroup',
            }
            EOS
            apply_manifest(pp2, catch_changes: true)
          end

          describe file('/etc/sysctl.d/98-sched_autogroup_enabled.conf') do
            it { is_expected.to be_file }
            its(:content) { is_expected.to match %r{kernel.sched_autogroup_enabled = 1} }
          end
        end
      end
    end
  end
end
