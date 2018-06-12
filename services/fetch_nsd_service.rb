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
require 'net/http'
require 'ostruct'
require 'json'

class FetchNSDService  
  ERROR_NS_UUID_IS_MANDATORY='Network Service UUID parameter is mandatory'
  NO_CATALOGUES_URL_DEFINED_ERROR='The CATALOGUES_URL ENV variable needs to defined and pointing to the Catalogue where to fetch services'
  CATALOGUES_URL = ENV.fetch('CATALOGUES_URL', '')
  
  def self.call(params)
    msg=self.name+'#'+__method__.to_s
    if CATALOGUES_URL == ''
      STDERR.puts "%s - %s: %s" % [Time.now.utc.to_s, msg, NO_CATALOGUES_URL_DEFINED_ERROR]
      return nil 
    end
    STDERR.puts "#{msg}: params=#{params}"
    begin
      if params.key?(:uuid)
        uuid = params.delete :uuid
        uri = URI.parse(CATALOGUES_URL+'/network-services/'+uuid)
        # mind that there cany be more params, so we might need to pass params as well
      else
        uri = URI.parse(CATALOGUES_URL+'/network-services')
        uri.query = URI.encode_www_form(sanitize(params))
      end
      #STDERR.puts "#{msg}: querying uri=#{uri}"
      request = Net::HTTP::Get.new(uri)
      request['content-type'] = 'application/json'
      response = Net::HTTP.start(uri.hostname, uri.port) {|http| http.request(request)}
      STDERR.puts "#{msg}: response=#{response}"
      return JSON.parse(response.read_body, quirks_mode: true, symbolize_names: true) if response.is_a?(Net::HTTPSuccess)
    rescue Exception => e
      STDERR.puts "%s - %s: %s" % [Time.now.utc.to_s, msg, e.message]
    end
    raise ArgumentError.new("Fetching service with params #{params}, got #{response}")
  end
end

