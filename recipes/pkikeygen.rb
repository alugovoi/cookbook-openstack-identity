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

require 'uri'

class ::Chef::Recipe # rubocop:disable Documentation
  include ::Openstack
end

# Install python keystone libraries needed for generating PKI keys
package "python-keystone"

# Copy keystone-manage bindary to a location where we will run it
#execute "Fetching keystone-manage binary" do
#  cwd '/tmp'
#  command "wget https://github.com/openstack/keystone/blob/stable/havana/bin/keystone-manage && chmod 755 keystone-manage"
#  not_if { ::File.exists?("/tmp/keystone-manage")}
#end
remote_file '/tmp/keystone-manage' do
  source "https://github.com/openstack/keystone/blob/stable/havana/bin/keystone-manage"
  mode 0755
end

def copy_file_to_web_share(uri)
  uri = URI.parse('http://192.168.112.11/cblr/localmirror/substructure/assets/signing_cert.pem')
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
  local_src_path = '/etc/keystone/ssl/' + filename
  file local_dst_path do
    mode 0644
    content ::File.open(local_src_path).read
    action :create
  done
end

if node['openstack']['auth']['strategy'] == 'pki'
  certfile_url = node['openstack']['identity']['signing']['certfile_url']
  keyfile_url = node['openstack']['identity']['signing']['keyfile_url']
  ca_certs_url = node['openstack']['identity']['signing']['ca_certs_url']
  signing_basedir = node['openstack']['identity']['signing']['basedir']

  if certfile_url.nil? || keyfile_url.nil? || ca_certs_url.nil?
    Chef::Application.fatal!("You need to define certfile_url, keyfile_url, and ca_certs_url so that the keystone SSL certs/keys can be set the same across all controller nodes.  See san3.rb in openstack-base for an example of this.")
  else
    # Run keystone-manage to generate PKI keys
    execute 'Generating PKI keys for Keystone' do
      command "/tmp/keystone-manage pki_setup 0 0"
      not_if { ::FileTest.exists? node['openstack']['identity']['signing']['keyfile'] }
    end

    # Copy PKI keys to a place where controller nodes running the openstack-identity::server recipe expect to find them over HTTP
    copy_file_to_web_share(certfile_url)
    copy_file_to_web_share(keyfile_url)
    copy_file_to_web_share(ca_certs_url)
  end
end
