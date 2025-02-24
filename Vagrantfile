# This Vagrantfile is used to test the script

# To run the script on all machines, export VAGRANT_AUTOSTART=true
autostart_machines = ENV['VAGRANT_AUTOSTART'] == 'true' || false
# else, run `vagrant up <hostname>`

machines = [
  # { hostname: 'debian-10', box: 'debian/stretch64' },
  # { hostname: 'debian-9', box: 'debian/stretch64' },
  # { hostname: 'debian-8', box: 'debian/jessie64' },
  { hostname: 'ubuntu-1604', box: 'ubuntu/bionic64' }
  # { hostname: 'ubuntu-1804', box: 'ubuntu/xenial64' }
]

Vagrant.configure('2') do |config|
  machines.each do |machine|
    config.vm.provider 'virtualbox' do |v|
      v.memory = 1024
      v.cpus = 2
    end
    config.vm.define machine[:hostname], autostart: autostart_machines do |machineconfig|
      machineconfig.vm.hostname = machine[:hostname]
      machineconfig.vm.box = machine[:box]

      machineconfig.vm.provision 'shell', inline: <<-SHELL
        AUTO_INSTALL=y /vagrant/openvpn-install.sh
        ps aux | grep openvpn | grep -v grep > /dev/null 2>&1 && echo "Success: OpenVPN is running" && exit 0 || echo "Failure: OpenVPN is not running" && exit 1
      SHELL
    end
  end
end
