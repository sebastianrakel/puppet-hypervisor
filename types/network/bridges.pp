type Hypervisor::Network::Bridges = Hash[String, Struct[
  {
    Optional[address_v4]          => Variant[Enum['dhcp'], Stdlib::IP::Address::V4],
    Optional[address_v6]          => Stdlib::IP::Address::V6,
    Optional[attach_to_interface] => String,
    Optional[vlan]                => Integer,
    Optional[dhcp_pool_offset]    => Integer,
    Optional[dhcp_pool_size]      => Integer,
    Optional[mtu]                 => Integer,
  }
]]
