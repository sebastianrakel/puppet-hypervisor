# frozen_string_literal: true

require 'spec_helper'

describe 'hypervisor' do

  on_supported_os.each do |os, facts|
    context "on #{os}" do
      context 'with bridges defined' do
        let :params do
          {
            bridges: {
              'intern': {
                'address_v4' => '192.168.122.1/24',
                'dhcp_pool_offset' => 20,
                'dhcp_pool_size' => 100
              }
            },
          }
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('hypervisor') }
      end
    end
  end
end
