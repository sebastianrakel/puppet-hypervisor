class hypervisor (
  Boolean $purge_netplan = true,
  Boolean $manage_firewall = true,
  Boolean $drop_libvirt_default_net = true,
  Hash[String, Hash] $interfaces = {},
  Hypervisor::Network::Bridges $bridges = {},
  Hash[String, Hash] $images = {},
  Hash[String, Hash] $vms = {},
) {
  class { 'libvirt':
    drop_default_net => $drop_libvirt_default_net,
  }

  $packages = [
    'qemu-utils',
    'cloud-image-utils',
  ]

  package{ $packages:
    ensure => installed,
  }

  if ($purge_netplan) {
    file {'/usr/lib/systemd/system-generators/netplan':
      ensure => absent,
      force  => true,
    }

    package { 'netplan.io':
      ensure => purged,
    }
  }

  $bridges.each | String $bridge_name, Any $bridge | {
    hypervisor::network::bridge { $bridge_name:
      * => $bridge,
    }
  }

  $interface_map = $bridges.reduce({}) |$acc, $bridge_data| {
    $bridge_name = "br-${bridge_data[0]}0"
    $bridge_config = $bridge_data[1]

    if $bridge_config['attach_to_interface'] {
      $interface = $bridge_config['attach_to_interface']
      $vlan = $bridge_config['vlan']

      $existing = $acc[$interface] ? {
        undef   => { 'bridges' => [], 'vlans' => [] },
        default => $acc[$interface]
      }

      if (!$vlan) {
        $new_bridges = $existing['bridges'] + [$bridge_name]
      } else {
        $new_bridges = $existing['bridges']
      }

      $new_vlans = $vlan ? {
        undef   => $existing['vlans'],
        default => $existing['vlans'] + [$vlan]
      }

      $acc + { $interface => {
        'bridges' => $new_bridges,
        'vlans' => $new_vlans
      }}
    } else {
      $acc
    }
  }

  $interfaces.each |String $interface, Hash $infos| {
    systemd::network { "${interface}.network":
      restart_service => true,
      content         => epp("${module_name}/network/network.epp", {
        interface_name => $interface,
        address_v4     => $infos['address_v4'],
        address_v6     => $infos['address_v6'],
        gateway        => $infos['gateway'],
        vlans          => $interface_map[$interface]['vlans'],
        bridges        => $interface_map[$interface]['bridges'],
      }),
    }
  }

  $images.each |String $image_name, Hash $params| {
    hypervisor::image { $image_name:
      * => $params,
    }
  }
  
  $vms.each |String $vm_name, Hash $params| {
    hypervisor::vm { $vm_name:
      * => $params,
    }
  }
}
