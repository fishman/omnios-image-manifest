#!/bin/env ruby
require 'date'
require 'net/http'
require 'json'
require 'nokogiri'
require 'erb'

$template = ERB.new <<-JSON
{
    "v": 2,
    "uuid": "<%= uuid %>",
    "owner": "00000000-0000-0000-0000-000000000000",
    "name": "<%= name %>",
    "version": "<%= version %>",
    "state": "enabled",
    "disabled": true,
    "public": true,
    "published_at": "<%= published_at %>",
    "type": "zvol",
    "os": "linux",
    "files": [
      {
        "sha1": "<%= sha1 %>",
        "size": "<%= size %>",
        "compression": "xz"
      }
    ],
    "description": "Omnios LX image",
    "homepage": "https://omnios.org",
    "tags": {
      "role": "os"
    }
  }
JSON

def trim(str)
  str.gsub(/\s+/, "")
end

def sha1sum(filename)
  Digest::SHA1.file(filename).hexdigest
end

def download_file(url, filename)
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    request = Net::HTTP::Get.new uri

    http.request request do |response|
      open filename, 'w' do |io|
        response.read_body do |chunk|
          io.write chunk
        end
      end
    end
  end
end

def list_omnios_lx_images
  omnios_base = 'https://downloads.omnios.org/media/lx/'
  uri = URI(omnios_base)
  html = Net::HTTP.get(uri)
  names = {}
  parsed_html = Nokogiri::HTML(html)
  parsed_html.css('a').each do |link|
    if /.tar.xz$/.match(link.content)
      date_match = /\d\d\d\d-\d\d-\d\d_\d\d-\d\d-\d\d/.match(link.content)
      date = date_match[0]
      names[link.content] = {
        'url' => "#{omnios_base}#{link['href']}",
        'uuid' => "#{omnios_base}#{link.content}.uuid",
        'sha256' => "#{omnios_base}#{link.content}.sha256",
        'date' => Date.strptime(date, '%Y-%m-%d_%H-%M-%S')
      }
    end
  end
  names
end

images = list_omnios_lx_images

def prompt_input(images)
  num = 0
  names = images.collect do |name, data|
    puts "#{num}: #{name}"
    num += 1
    name
  end

  puts 'Which image would you like to import?'
  input = gets.chomp
  name = names[input.to_i]
  puts images[name]['url']
  puts images[name]['uuid']

  download_file(images[name]['uuid'], name + '.uuid')
  download_file(images[name]['url'], name)
  # download_file(images[name]['sha256'], name + '.sha256')

  uuid = trim File.read(name + '.uuid')
  version = "1.0"
  published_at = images[name]['date'].strftime('%Y-%m-%dT%H:%M:%SZ')
  sha1 = sha1sum(name)
  size = File.size(name)

  manifest = $template.result(binding)
  # Write manifest to file
  File.write(name + '.manifest', manifest)
  system("imgadm", "install -m #{manifest} -f #{name}")
end

prompt_input(images)
