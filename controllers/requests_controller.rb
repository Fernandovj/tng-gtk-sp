## Copyright (c) 2015 SONATA-NFV, 2017 5GTANGO [, ANY ADDITIONAL AFFILIATION]
## ALL RIGHTS RESERVED.
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
## Neither the name of the SONATA-NFV, 5GTANGO [, ANY ADDITIONAL AFFILIATION]
## nor the names of its contributors may be used to endorse or promote
## products derived from this software without specific prior written
## permission.
##
## This work has been performed in the framework of the SONATA project,
## funded by the European Commission under Grant number 671517 through
## the Horizon 2020 and 5G-PPP programmes. The authors would like to
## acknowledge the contributions of their colleagues of the SONATA
## partner consortium (www.sonata-nfv.eu).
##
## This work has been performed in the framework of the 5GTANGO project,
## funded by the European Commission under Grant number 761493 through
## the Horizon 2020 and 5G-PPP programmes. The authors would like to
## acknowledge the contributions of their colleagues of the 5GTANGO
## partner consortium (www.5gtango.eu).
# encoding: utf-8
require 'sinatra'
require 'json'
require 'sinatra/activerecord'
require 'tng/gtk/utils/logger'
require 'tng/gtk/utils/application_controller'
require 'tng/gtk/utils/services'
require_relative '../services/process_request_base'
require_relative '../services/process_request_service'
require_relative '../services/process_create_slice_instance_request'
require_relative '../services/process_terminate_slice_instance_request'

class RequestsController < Tng::Gtk::Utils::ApplicationController
  LOGGER=Tng::Gtk::Utils::Logger
  LOGGED_COMPONENT=self.name
  @@began_at = Time.now.utc
  LOGGER.info(component:LOGGED_COMPONENT, operation:'initializing', start_stop: 'START', message:"Started at #{@@began_at}")
  ERROR_REQUEST_CONTENT_TYPE={error: "Unsupported Media Type, just accepting 'application/json' HTTP content type for now."}
  ERROR_SERVICE_NOT_FOUND="Network Service with UUID '%s' was not found in the Catalogue."
  ERROR_PARSING_NS_DESCRIPTOR="There was an error parsing the NS descriptor with UUID '%s'."
  ERROR_CONNECTING_TO_CATALOGUE={error: "There was an error connecting to the Catalogue."}
  ERROR_EMPTY_BODY = <<-eos 
  The request was missing a body with:
     \tservice_uuid: the UUID of the service to be instantiated
     \trequest_type: can be CREATE_SERVICE (default), TERMINATE_SERVICE, CREATE_SLICE or TERMINATE_SLICE
     \tegresses: the list of required egresses (defaults to [])
     \tingresses: the list of required ingresses (defaults to [])
  eos
  #ERROR_SERVICE_UUID_IS_MISSING="Service UUID is a mandatory parameter (absent from the '%s' request)"
  ERROR_REQUEST_NOT_FOUND="Request with UUID '%s' was not found"
  
  # From http://gavinmiller.io/2016/the-safesty-way-to-constantize/
  STRATEGIES = {
    'CREATE_SERVICE': ProcessRequestService,
    'TERMINATE_SERVICE': ProcessRequestService,
    'CREATE_SLICE': ProcessCreateSliceInstanceRequest,
    'TERMINATE_SLICE': ProcessTerminateSliceInstanceRequest
  }

  #after  {ActiveRecord::Base.clear_active_connections!}
  after  {ActiveRecord::Base.clear_all_connections!}

  # Accept service instantiation requests
  post '/?' do
    msg='.'+__method__.to_s
    LOGGER.info(component:LOGGED_COMPONENT, operation:msg, message:"entered")
    unless request.content_type =~ /^application\/json/
      LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"Unsupported Media Type, just accepting 'application/json' HTTP content type for now.")
      halt_with_code_body(415, ERROR_REQUEST_CONTENT_TYPE.to_json) 
    end

    body = request.body.read
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"body=#{body}")
    halt_with_code_body(400, ERROR_EMPTY_BODY.to_json) if body.empty?
    
    begin
      json_body = JSON.parse(body, quirks_mode: true, symbolize_names: true)
      json_body[:request_type] = 'CREATE_SERVICE' unless json_body.key?(:request_type)
      json_body[:customer_name] = request.env['5gtango.user.name']
      json_body[:customer_email] = request.env['5gtango.user.email']
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"json_body=#{json_body}")
    
      saved_request = strategy(json_body[:request_type]).call(json_body.deep_symbolize_keys)
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"saved_request='#{saved_request.inspect}'")
      unless saved_request
        LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"Error saving request")
        halt_with_code_body(400, {error: "Error saving request"}.to_json) 
      end
      # for the special case of CREATE_SLICE, the returned data structure is not an Hash
      if (saved_request && saved_request.is_a?(Hash) && saved_request.key?(:error) && !saved_request[:error].to_s.empty?)
        LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:saved_request[:error].to_json)
        halt_with_code_body(404, {error: saved_request[:error]}.to_json) 
      end
      result = strategy(json_body[:request_type]).enrich_one(saved_request)
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"result=#{result}", status: '201')
      halt_with_code_body(201, result.to_json)
    rescue KeyError => e
      LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"Missing code to treat the '#{json_body[:request_type]}' request type", status: '404')
      halt_with_code_body(404, {error: "Missing code to treat the '#{json_body[:request_type]}' request type"}.to_json)
    rescue ArgumentError => e
      LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"#{e.message} for #{params}\n#{e.backtrace.join("\n\t")}", status: '404')
      halt_with_code_body(404, {error: "#{e.message} for #{params}"}.to_json)
    rescue JSON::ParserError => e
      LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:ERROR_PARSING_NS_DESCRIPTOR % params[:service_uuid], status: '400')
      halt_with_code_body(400, {error: ERROR_PARSING_NS_DESCRIPTOR % params[:service_uuid]}.to_json)
    rescue StandardError => e
      LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"#{e.message}\n#{e.backtrace.join("\n\t")}", status: '500')
      halt_with_code_body(500, "#{e.message}\n#{e.backtrace.join("\n\t")}")
    end
  end
  
  # GETs a request, given an uuid
  get '/:request_uuid/?' do
    msg='.'+__method__.to_s
    LOGGER.info(component:LOGGED_COMPONENT, operation:msg, message:"entered with params='#{params}'")
    captures=params.delete('captures') if params.key? 'captures'
    begin
      single_request = ProcessRequestBase.find(params[:request_uuid], RequestsController::STRATEGIES)
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"single_request='#{single_request}'")
      if (!single_request || single_request.empty?)
        LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:ERROR_REQUEST_NOT_FOUND % params[:request_uuid], status: '404')
        halt_with_code_body(404, {error: ERROR_REQUEST_NOT_FOUND % params[:request_uuid]}.to_json) 
      end
      LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:single_request.to_json, status: '200')
      halt_with_code_body(200, single_request.to_json)
    rescue Exception => e
			ActiveRecord::Base.clear_active_connections!
      LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:e.message, status: '404')
      halt_with_code_body(404, {error: e.message}.to_json)
      raise
    end
  end

  # GET many requests
  get '/?' do
    msg='.'+__method__.to_s
    captures=params.delete('captures') if params.key? 'captures'
    LOGGER.info(component:LOGGED_COMPONENT, operation:msg, message:"entered with params='#{params}'")
    
    # get rid of :page_size and :page_number
    page_number, page_size, sanitized_params = sanitize(params)
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"page_number, page_size, sanitized_params=#{page_number}, #{page_size}, #{sanitized_params}")
    begin
      requests = ProcessRequestBase.search( page_number, page_size, RequestsController::STRATEGIES)
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"requests='#{requests.inspect}'")
      headers 'Record-Count'=>requests.size.to_s, 'Content-Type'=>'application/json'
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:requests.to_json, status: '200')
      halt 200, requests.to_json
    rescue ActiveRecord::RecordNotFound => e
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:'[]', status: '200')
      halt 200, '[]'
    rescue Exception => e
      LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"Exception caught, ActiveRecord::Base.clear_active_connections!\n#{e.message}\n#{e.backtrace.join("\n\t")}", status: '500')
			ActiveRecord::Base.clear_active_connections!
      raise
    end
  end
  
  options '/?' do
    msg='.'+__method__.to_s
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET,DELETE'      
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With'
    halt 200
  end
  
  # Callback for the tng-slice-mngr to notify the result of processing
  post '/:request_uuid/on-change/?' do
    msg='.'+__method__.to_s
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"entered, request_uuid=#{params[:request_uuid]}, params=#{params}")
    
    begin
      body = request.body.read
      #halt_with_code_body(400, "The callback is missing the event data") if 
      event_data = body.empty? ? {} : JSON.parse(body, symbolize_names: true)

      event_data[:original_event_uuid] = params[:request_uuid]
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"event_data=#{event_data}")
      original_request = Request.find(params[:request_uuid])
      unless original_request
        LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"Request #{params[:request_uuid]} was not found", status: '404')
        halt 404, {}, {error: "Request #{params[:request_uuid]} was not found"}.to_json
      end
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"original_request=#{original_request.inspect}")
      request_type = original_request.request_type
      unless request_type
        LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"Request type of request #{original_request.inspect} was not found", status: '404')
        halt 404, {}, {error: "Request type of request #{original_request.inspect} was not found"}.to_json
      end
      unless strategy(request_type)
        LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"Request type #{request_type} is not valid", status: '404')
        halt 400, {}, {error: "Request type #{request_type} is not valid"}.to_json
      end
      #result = ProcessCreateSliceInstanceRequest.process_callback(event_data)
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"Processing callback...")
      result = strategy(request_type).process_callback(event_data)
      
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"Callback processed, result=#{result}")
      unless result.empty?
        LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:result.to_json, status: '201')
        halt 201, {'Content-Type'=>'application/json'}, result.to_json 
      end
      LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"Package processing UUID not found in event #{event_data}", status: '404')
      halt 404, {}, {error: "Package processing UUID not found in event #{event_data}"}.to_json
    rescue JSON::ParserError => e
      LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"Failling JSON interpretation of '#{body}'", status: '400')
      halt 400, {}, {error: "Failling JSON interpretation of '#{body}'"}.to_json
    rescue ActiveRecord::RecordNotFound, ArgumentError, NameError => e
      LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"#{e.message} #{params}\n#{e.backtrace.join("\n\t")}", status: '400')
      halt 400, {}, {error: e.message}.to_json
    end
  end  
  
  private
  def strategy(req_type)
    RequestsController::STRATEGIES.fetch(req_type.to_sym)
  end
  
  def halt_with_code_body(code, body)
    halt code, {'Content-Type'=>'application/json', 'Content-Length'=>body.length.to_s}, body
  end
  
  def validated_fields(params_keys)
    valid_fields = [:service_uuid, :status, :created_at, :updated_at]
    #logger.info(log_msg) {" keyed_params.keys - valid_fields = #{keyed_params.keys - valid_fields}"}
    json_error 400, "GtkSrv: wrong parameters #{params}" unless keyed_params.keys - valid_fields == []
  end
  
  def sanitize(params)
    params[:page_number] ||= ENV.fetch('DEFAULT_PAGE_NUMBER', 0)
    params[:page_size]   ||= ENV.fetch('DEFAULT_PAGE_SIZE', 100)
    page_number = params.delete(:page_number).to_i
    page_size = params.delete(:page_size).to_i
    return page_number, page_size, params
  end
  
  def symbolized_hash(hash)
    Hash[hash.map{|(k,v)| [k.to_sym,v]}]
  end
  LOGGER.info(component:LOGGED_COMPONENT, operation:'initializing', start_stop: 'STOP', message:"Ended at #{Time.now.utc}", time_elapsed:"#{Time.now.utc-began_at}")
end
