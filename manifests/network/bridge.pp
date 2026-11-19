# @summary
#   Creates a Linux bridge network for use with libvirt, managed via
#   systemd-networkd. Optionally configures a VLAN sub-interface, a DHCP
#   server, and the required nftables firewall rules.
#
# @param network_name
#   Name of the libvirt network and base name for the bridge interface
#   (`br-<network_name>0`). Defaults to the resource title.
#
# @param address_v4
#   IPv4 address to assign to the bridge interface, either as a CIDR string
#   (e.g. `'192.168.10.1/24'`) or the string `'dhcp'` to obtain an address
#   via DHCP. Omit to leave the bridge without an IPv4 address.
#
# @param network_v4
#   IPv4 network in CIDR notation (e.g. `'192.168.10.0/24'`). Required when
#   acting as a DHCP server (i.e. when both `dhcp_pool_offset` and
#   `dhcp_pool_size` are set). Used to generate masquerade and forwarding
#   firewall rules.
#
# @param dns_v4
#   IPv4 address of the DNS server advertised to DHCP clients. Only relevant
#   when the bridge is acting as a DHCP server.
#
# @param address_v6
#   IPv6 address to assign to the bridge interface in CIDR notation. Omit to
#   leave the bridge without an IPv6 address.
#
# @param attach_to_interface
#   Physical network interface to attach the bridge to. Required when `vlan`
#   is set. When provided, a systemd-networkd `.network` unit is created for
#   the interface (or the VLAN sub-interface) that enslaves it to the bridge.
#
# @param vlan
#   VLAN ID to create as a sub-interface on `attach_to_interface`. When set,
#   a VLAN `.netdev` and `.network` unit are created and the bridge is
#   attached to the VLAN sub-interface rather than directly to the physical
#   interface. Requires `attach_to_interface`.
#
# @param dhcp_pool_offset
#   Offset from the start of the network at which the DHCP address pool
#   begins. Must be set together with `dhcp_pool_size` to enable the built-in
#   DHCP server.
#
# @param dhcp_pool_size
#   Number of addresses in the DHCP pool. Must be set together with
#   `dhcp_pool_offset` to enable the built-in DHCP server.
#
# @param mtu
#   MTU to configure on the bridge interface. When `undef`, no `[Link]`
#   section is written to the systemd-networkd unit and the kernel default is
#   used.
#
# @param manage_firewall
#   When `true` and the bridge is acting as a DHCP server, creates nftables
#   rules to allow DNS (UDP/TCP 53), DHCP (UDP 67), forwarding of guest
#   traffic, and NAT masquerading for outbound traffic.
define hypervisor::network::bridge (
  String[1] $network_name = $name,
  Optional[Variant[Enum['dhcp'], Stdlib::IP::Address::V4]] $address_v4 = undef,
  Optional[Stdlib::IP::Address::V4::CIDR] $network_v4 = undef,
  Optional[Stdlib::IP::Address::V4] $dns_v4 = undef,
  Optional[Stdlib::IP::Address::V6] $address_v6 = undef,
  Optional[String] $attach_to_interface = undef,
  Optional[Integer] $vlan = undef,
  Optional[Integer] $dhcp_pool_offset = undef,
  Optional[Integer] $dhcp_pool_size = undef,
  Optional[Integer] $mtu = undef,
  Boolean $manage_firewall = true,
  Boolean $nat = false,
) {
  $bridge_interface_name = "br-${network_name}0"
  $is_dhcp_server = $dhcp_pool_size and $dhcp_pool_offset

  if ($is_dhcp_server and !$network_v4) {
    fail('network for dhcp server must be filled')
  }

  if ($vlan) {
    if ($attach_to_interface == undef) {
      fail('needs attach_to_interface')
    }

    $vlan_interface_name = "${attach_to_interface}.${vlan}"

    systemd::network { "${vlan_interface_name}.netdev":
      restart_service => true,
      content         => epp("${module_name}/network/netdev.epp", {
        interface_name => $vlan_interface_name,
        kind           => 'vlan',
        vlan           => $vlan
      }),
    }

    systemd::network { "${vlan_interface_name}.network":
      restart_service => true,
      content         => epp("${module_name}/network/network.epp", {
        interface_name => $vlan_interface_name,
        bridges        => [$bridge_interface_name],
      }),
    }
  }

  systemd::network { "${bridge_interface_name}.netdev":
    restart_service => true,
    content         => epp("${module_name}/network/netdev.epp", {
      interface_name => $bridge_interface_name,
      kind           => 'bridge',
    }),
  }

  systemd::network { "${bridge_interface_name}.network":
    restart_service => true,
    content         => epp("${module_name}/network/network.epp", {
      interface_name   => $bridge_interface_name,
      address_v4       => $address_v4,
      address_v6       => $address_v6,
      is_dhcp_server   => $is_dhcp_server,
      dhcp_pool_offset => $dhcp_pool_offset,
      dhcp_pool_size   => $dhcp_pool_size,
      has_link_section => $mtu != undef,
      mtu              => $mtu,
      dns_v4           => $dns_v4,
      nat              => $nat,
    }),
  }

  libvirt::network { $network_name:
    forward_mode => 'bridge',
    bridge       => $bridge_interface_name,
  }

  if ($is_dhcp_server and $manage_firewall) {
    nftables::rule {
      "default_in-qemu_udp_dns_${name}":
        content => "iifname \"${bridge_interface_name}\" udp dport 53 accept";
      "default_in-qemu_tcp_dns_${name}":
        content => "iifname \"${bridge_interface_name}\" tcp dport 53 accept";
    }

    nftables::rule {
      "default_in-qemu_dhcpv4_${name}":
        content => "iifname \"${bridge_interface_name}\" meta l4proto udp udp dport 67 accept";
    }

    nftables::rule {
      "default_fwd-qemu_oip_v4_${name}":
        content => "oifname \"${bridge_interface_name}\" ip daddr ${network_v4} ct state related,established accept";
      "default_fwd-qemu_iip_v4_${name}":
        content => "iifname \"${bridge_interface_name}\" ip saddr ${network_v4} accept";
    }

    nftables::rule {
      "default_fwd-qemu_io_internal_${name}":
        content => "iifname \"${bridge_interface_name}\" oifname \"${bridge_interface_name}\" accept",
    }

    nftables::rule {
      "POSTROUTING-qemu_ignore_multicast_${name}":
        table   => 'ip-nat',
        content => "ip saddr ${network_v4} ip daddr 224.0.0.0/24 return";
      "POSTROUTING-qemu_ignore_broadcast_${name}":
        table   => 'ip-nat',
        content => "ip saddr ${network_v4} ip daddr 255.255.255.255 return";
      "POSTROUTING-qemu_masq_tcp_${name}":
        table   => 'ip-nat',
        content => "meta l4proto tcp ip saddr ${network_v4} ip daddr != ${network_v4} masquerade to :1024-65535";
      "POSTROUTING-qemu_masq_udp_${name}":
        table   => 'ip-nat',
        content => "meta l4proto udp ip saddr ${network_v4} ip daddr != ${network_v4} masquerade to :1024-65535";
      "POSTROUTING-qemu_masq_ip_${name}":
        table   => 'ip-nat',
        content => "ip saddr ${network_v4} ip daddr != ${network_v4} masquerade";
    }
  }
}
