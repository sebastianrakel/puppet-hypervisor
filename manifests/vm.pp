define hypervisor::vm(
  String[1] $vm_name = $name,
  Integer $memory_mb,
  String $disk_size,
  String $disk_vg = 'vg0',
  Boolean $autostart = true,
  String[1] $image_directory = "/var/lib/libvirt/images",
  Optional[String] $iso = undef,
  Optional[String] $base_image = undef,
  Optional[Hash] $cloud_init_config = undef,
  Array[String] $networks = ['default'],
  Hash[String, Hash] $additional_disks = {},
  Boolean $uefi = false,
  Optional[String] $cpu_model = undef,
  Array[String] $additional_isos = [],
  Integer $cpu_count = 1,
) {
  $disk_name = "${vm_name}_disk"

  logical_volume { $disk_name:
    ensure       => present,
    volume_group => $disk_vg,
    size         => $disk_size,
  }

  if ($base_image) {
    exec {"convert to physical disk ${vm_name}":
      command     => "qemu-img convert -f qcow2 -O raw ${base_image} /dev/${disk_vg}/${disk_name}",
      cwd         => $image_directory,
      path        => '/usr/bin',
      refreshonly => true,
      subscribe   => Logical_Volume[$disk_name],
    }
  }
 
  if ($iso) {
    $iso_disk = [{
      'type'   => 'file',
      'device' => 'cdrom',
      'bus'    => 'sata',
      'source' => {
        'file' => "${image_directory}/${iso}"
      },
      'driver' => {
        'name'  => 'qemu',
        'type'  => 'raw',
      },
    }]
  } else {
    $iso_disk = []
  }

  $final_additional_isos = $additional_isos.map |String $additonal_iso| {
    {
      'type'   => 'file',
      'device' => 'cdrom',
      'bus'    => 'sata',
      'source' => {
        'file' => "${image_directory}/${additonal_iso}"
      },
      'driver' => {
        'name'  => 'qemu',
        'type'  => 'raw',
      },
    }
  }

  if ($cloud_init_config) {
    $cloud_init_image = "${image_directory}/${vm_name}-cloud-init.img"
    
    file { "${image_directory}/${vm_name}_cloud_init.cfg":
      ensure  => 'file',
      content => epp("${module_name}/cloud_init.cfg.epp", {
        data => $cloud_init_config
      }),
    }
    
    exec {"create cloud_init.cfg ${vm_name}":
      command => "cloud-localds ${vm_name}-cloud-init.img ${vm_name}_cloud_init.cfg",
      cwd     => $image_directory,
      path    => '/usr/bin',
      creates => $cloud_init_image,
    }

    $cloud_init_disk = [{
      'type'   => 'file',
      'device' => 'cdrom',
      'bus'    => 'sata',
      'source' => {
        'file' => $cloud_init_image
      },
      'driver' => {
        'name'  => 'qemu',
        'type'  => 'raw',
      },
    }]
  } else {
    $cloud_init_disk = []
  }

  if ($additional_disks.length > 0) {
    $additional_disks.each |String $disk_name, Hash $options|{
      $vg = $options['vg']
      $full_disk_name = "${vm_name}_${disk_name}"
      
      logical_volume { $full_disk_name:
        ensure       => present,
        volume_group => $vg,
        size         => $options['size'],
      }
    }
    
    $libvirt_additional_disks = $additional_disks.map |String $disk_name, Hash $options|{
      {
        'type'   => 'block',
        'device' => 'disk',
        'bus'    => 'virtio',
        'source' => {
          'dev' => "/dev/${options['vg']}/${vm_name}_${disk_name}",
        },
        'driver' => {
          'name' => 'qemu',
          'type' => 'raw',
        },
      }
    }
  } else {
    $libvirt_additional_disks = []
  }

  $vm_networks = $networks.map |String $network|{
    {'network' => $network}
  }

  $domconfig = {
    vcpu => {
      values => $cpu_count,
      attrs => {
        placement => 'static',
      },
    },
    memory => {
      values => $memory_mb,
      attrs  => {
        unit => 'MiB',
      },
    },
  }

  if ($uefi) {
    $domconfig_uefi = {
      os => {
        values   => {
          type     => {
            attrs => {
              arch => 'x86_64',
              machine => 'q35',
            },
            values => 'hvm'
          },
          loader   => {
            attrs  => {
              readonly => 'yes',
              type     => 'pflash',
            },
            values => '/usr/share/OVMF/OVMF_CODE_4M.ms.fd',
          }
        }
      }
    }
  } else {
    $domconfig_uefi = {}
  }

  if ($cpu_model != undef) {
    $domconfig_cpu = {
      cpu => {
        attrs => {
          mode  => 'custom',
          match => 'exact',
          check => 'partial',
        },
        values   => {
          model => {
            attrs => {
              fallback  => 'allow',
            },
            values => $cpu_model,
          },
        }
      }
    }
  } else {
    $domconfig_cpu = {}
  }

  libvirt::domain { $vm_name:
    boot         => 'hd',
    domconf      => $domconfig + $domconfig_uefi + $domconfig_cpu,
    interfaces   => [] + $vm_networks,
    autostart    => $autostart,
    active       => true,
    replace      => true,
    disks        => [
      {
        'type'   => 'block',
        'device' => 'disk',
        'bus'    => 'virtio',
        'source' => {
          'dev' => "/dev/${disk_vg}/${disk_name}",
        },
        'driver' => {
          'name'  => 'qemu',
          'type'  => 'raw',
        },
      },
    ] + $iso_disk
      + $cloud_init_disk
      + $libvirt_additional_disks
      + $final_additional_isos,
  }
}
