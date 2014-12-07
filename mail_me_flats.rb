#!/usr/bin/env ruby

require "nokogiri"
require "open-uri"
require "mandrill"
require "dotenv"
Dotenv.load

@ebay_base_url = "http://kleinanzeigen.ebay.de"
@immoscout_base_url = "http://www.immobilienscout24.de"

immoscout_search_urls = ENV["IMMOSCOUT_URL"].split(';')
ebay_search_urls = ENV["KLEINANZEIGEN_URL"].split(';')

mandrill = Mandrill::API.new ENV["MANDRILL_APIKEY"]
file = File.open(File.join(File.dirname(File.expand_path(__FILE__)), "seen"), "a+")
@seen = file.readlines

def ebay(search_url)
  doc = Nokogiri::HTML(open("#{@ebay_base_url}#{search_url}"))

  doc.css("#srchrslt-adtable > li").map do |item|
    time_str = item.css(".ad-listitem-addon").text.strip
    time = Time.parse(time_str)
    if time_str.include? "Gestern"
      time = time - 86400
    end
    details = item.css(".ad-listitem-details").text.gsub(/\n\s*/," ").strip
    main = item.css(".ad-listitem-main").text.gsub(/\n\s*/," ").gsub("\r","").strip
    url = "#{@ebay_base_url}#{item.css(".ad-listitem-main > h2 > a").first["href"]}"
    {
      time: time,
      details: details,
      main: main,
      url: url
    } unless @seen.include? "#{url}\n"
  end
end

def immoscout(search_url)
  immo_doc = Nokogiri::HTML(open("#{@immoscout_base_url}#{search_url}"))

  immo_doc.css("#resultListItems > li").reject { |li| li.css("a").count == 0 }.map do |li|
    expose_href = li.css("a").reject { |a| a["title"] == nil }.first

    expose_title = expose_href["title"]
    expose_link = "#{@immoscout_base_url}#{expose_href["href"]}"

    expose_details = [
      li.css(".street").text.split(" | ").last,
      li.css(".resultlist_criteria > dl").map { |dl| "#{dl.css("dd").text.strip} #{dl.css("dt").text.strip}" }.join(", "),
      li.css(".criteria_secondary_box > ul > li").map { |li| li.text.strip }.join(", ")
    ].join(", ")

    {
      details: expose_details,
      title: expose_title,
      url: expose_link
    } unless @seen.include? "#{expose_link}\n"
  end
end

begin
  whngs = []
  whngs += ebay_search_urls.map do |url|
    ebay(url)
  end.flatten
  whngs += immoscout_search_urls.map do |url|
    immoscout(url)
  end.flatten

  unless whngs.compact.length == 0
    message = {
      subject: ENV["EMAIL_SUBJECT"],
      from_name: ENV["EMAIL_FROM_NAME"],
      text: whngs.map { |e| e.values.join " " }.join("\n"),
      to: [{
            email: ENV["EMAIL_TO"],
            name: ENV["EMAIL_TO_NAME"]
           }],
      from_email: ENV["EMAIL_FROM"]
      }
    sending = mandrill.messages.send message
    if sending[0]["status"] == "sent"
      file.write(whngs.compact.map { |e| e[:url] }.join("\n")+"\n")
    end
  end

rescue Exception => e
  puts "ERROR: #{e}"
end
