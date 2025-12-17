# frozen_string_literal: true

require 'spec_helper'

describe 'hypervisor::network::bridge', type: :define do
  let(:title) { 'intern' }

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let :facts do
        os_facts
      end

      context 'internal network with dhcp' do
        let :params do
          {
            address_v4: '192.168.122.1/24',
            network_v4: '192.168.122.0/24',
            dhcp_pool_offset: 20,
            dhcp_pool_size: 100
          }
        end

        let(:expected_netdev_content) do
          File.read('spec/fixtures/test_files/intern.netdev')
        end

        let(:expected_network_content) do
          File.read('spec/fixtures/test_files/intern.network')
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_systemd__network("br-#{title}0.netdev").with_content(expected_netdev_content) }
        it { is_expected.to contain_systemd__network("br-#{title}0.network").with_content(expected_network_content) }
      end
    end
  end
end
