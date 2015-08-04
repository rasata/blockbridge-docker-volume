# Copyright (c) 2015, Blockbridge Networks LLC.  All rights reserved.
# Use of this source code is governed by a BSD-style license, found
# in the LICENSE file.

require 'goliath'
require 'grape'
require 'docker'
require 'helpers'

module Blockbridge
  class VolumeDriverAPI < Grape::API
    #version 'v1', using: :header, vendor: 'docker.plugins'
    format :json
    default_format :json

    rescue_from :all do |e|
      msg = e.message.chomp.squeeze("\n")
      msg.each_line do |m| env.logger.error(m.chomp) end
      e.backtrace.each do |b| env.logger.error(b) end
      error!(Err: msg)
    end

    before do
      status 200
      check_name
      check_iscsid
    end

    helpers Blockbridge::Helpers

    resource 'Plugin.Activate' do
      desc "Activate Volume Driver"
      post do
        {
          Implements: ["VolumeDriver"]
        }
      end
    end

    resource 'VolumeDriver.Create' do
      desc "Create a Volume"
      params do
        requires :Name, type: String, desc: "Volume Name"
      end
      post do
        volume_create
        begin
          volume_provision
          volume_mkfs
        rescue
          volume_create_fail
          raise
        end
        {
          Err: nil,
        }
      end
    end

    resource 'VolumeDriver.Remove' do
      desc "Remove a Volume"
      params do
        requires :Name, type: String, desc: "Volume Name"
      end
      post do
        volume_remove
        {
          Err: nil,
        }
      end
    end

    resource 'VolumeDriver.Mount' do
      desc "Mount a Volume"
      params do
        requires :Name, type: String, desc: "Volume Name"
      end
      post do
        volume_attach
        volume_mount
        {
          Mountpoint: mnt_path,
          Err: nil,
        }
      end
    end

    resource 'VolumeDriver.Path' do
      desc "Query path of a Volume"
      params do
        requires :Name, type: String, desc: "Volume Name"
      end
      post do
        {
          Mountpoint: mnt_path,
          Err: nil,
        }
      end
    end

    resource 'VolumeDriver.Unmount' do
      desc "Unmount a Volume"
      params do
        requires :Name, type: String, desc: "Volume Name"
      end
      post do
        volume_unmount
        volume_detach
        {
          Err: nil,
        }
      end
    end
  end

  Goliath::Request.log_block = proc do |env, response, elapsed_time|
    env.logger.debug do
      full_uri = env['PATH_INFO']
      if (query_string = env['QUERY_STRING']) && !query_string.empty?
        full_uri += "?" + query_string
      end
  
      "#{env['HTTP_X_FORWARDED_FOR'] || env['REMOTE_ADDR'] || '-'} " \
      "#{env['REMOTE_USER'] || '-'} " \
      "\"#{env['REQUEST_METHOD']} #{full_uri} #{env['HTTP_VERSION']}\" " \
      "#{response.status} " \
      "#{response.headers['Content-Length'] || '-'} " \
      "[#{"%.2f" % elapsed_time}ms]"
    end
  end

  class VolumeDriver < Goliath::API
    use Goliath::Rack::Render # auto-negotiate response format
    use Goliath::Rack::Params # parse & merge query and body parameters
    use Goliath::Rack::Validation::RequestMethod, %w(POST) # allow POST requests only

    # docker api version
    Docker.validate_version!

    # process api call
    def response(env)
      Blockbridge::VolumeDriverAPI.call(env)
    end
  end
end
