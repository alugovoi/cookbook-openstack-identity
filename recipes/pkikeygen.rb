# encoding: UTF-8
#
# Cookbook Name:: openstack-identity
# Recipe:: pkikeygen
#
# Copyright 2012, Rackspace US, Inc.
# Copyright 2012-2013, Opscode, Inc.
# Copyright 2013 SUSE LINUX Products GmbH.
#
# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class ::Chef::Recipe # rubocop:disable Documentation
  include ::Openstack
end

if node['openstack']['auth']['strategy'] == 'pki'
  certfile_url = node['openstack']['identity']['signing']['certfile_url']
  keyfile_url = node['openstack']['identity']['signing']['keyfile_url']
  ca_certs_url = node['openstack']['identity']['signing']['ca_certs_url']
  signing_basedir = node['openstack']['identity']['signing']['basedir']

  if certfile_url.nil? || keyfile_url.nil? || ca_certs_url.nil?
    Chef::Application.fatal!("You need to define certfile_url, keyfile_url, and ca_certs_url so that the keystone SSL certs/keys can be set the same across all controller nodes.  See san3.rb in openstack-base for an example of this.")
  else

    # Install python keystone libraries needed for generating PKI keys
    package "python-keystone"

    # Copy keystone-manage bindary to a location where we will run it
    remote_file '/tmp/keystone-manage' do
      source "https://github.com/openstack/keystone/raw/stable/havana/bin/keystone-manage"
      mode 0755
    end

    # Run keystone-manage to generate PKI keys
    execute 'Generating PKI keys for Keystone' do
      command "/tmp/keystone-manage pki_setup --keystone-user 0 --keystone-group 0"
      not_if { ::FileTest.exists? node['openstack']['identity']['signing']['keyfile'] }
    end

    # Copy PKI keys to a place where controller nodes running the openstack-identity::server recipe expect to find them over HTTP
    ruby_block "copy keystone cert/key files" do
      block do

        require 'uri'
        require 'fileutils'
        require 'find'

        def copy_file_to_web_share(input_url)
          uri = URI.parse(input_url)
          scheme = uri.scheme
          host = uri.host
          path = uri.route_from("#{scheme}://#{host}").path
          path_split = path.split("/")
          path_split.shift
          filename = path_split.pop
          # files are hosted from a1r1 starting under /usr/share/cobbler/webroot/cobbler
          if path_split[0] == "cblr" or path_split[0] == "cobbler"
            path_split[0] = 'cobbler'
            path_split.unshift('webroot')
            path_split.unshift('cobbler')
            path_split.unshift('share')
            path_split.unshift('usr')
          end
          path_split.push(filename)
          path_split.unshift('')
          local_dst_path = path_split.join("/")
          local_src_path = ''
          Find.find('/etc/keystone/ssl') do |searchmatch|
            local_src_path = searchmatch if searchmatch =~ /#{filename}/
          end
          FileUtils.cp local_src_path, local_dst_path
          FileUtils.chmod 0644, local_dst_path
          return
        end

        copy_file_to_web_share node['openstack']['identity']['signing']['certfile_url']
        copy_file_to_web_share node['openstack']['identity']['signing']['keyfile_url']
        copy_file_to_web_share node['openstack']['identity']['signing']['ca_certs_url']
      end
    end
  end
end
