type Hypervisor::Network::Bridge = Struct[{
  network_name        => String[1],
  address_v4          => Optional[Variant[Enum['dhcp'], Stdlib::IP::Address::V4]],
  address_v6          => Optional[Stdlib::IP::Address::V6],
  attach_to_interface => Optional[String],
  vlan                => Optional[Integer],
  dhcp_address_start  => Optional[Integer],
  dhcp_address_size   => Optional[Integer],
  mtu                 => Optional[Integer],
}]
