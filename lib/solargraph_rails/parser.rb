# frozen_string_literal: true

module SolargraphRails
  class Parser
    attr_reader :contents, :path

    def initialize(path, contents)
      @path = path
      @contents = contents
    end

    def parse
      model_attrs = []
      model_name = nil
      line_number = -1
      contents.lines do |line|
        line_number += 1
        log_message :info, "PROCESSING: #{line}"

        next if skip_line?(line)

        if is_comment?(line)
          col_name, col_type = col_with_type(line)
          if type_translation.keys.include?(col_type)
            log_message :info, "parsed name: #{col_name} type: #{col_type}"

            loc = Solargraph::Location.new(path, Solargraph::Range.from_to(line_number, 0, line_number, line.length - 1))
            log_message :info, loc.inspect

            model_attrs << {name: col_name, type: col_type, location: loc}
          else
            log_message :info, "could not find annotation in comment"
            next
          end
        else
          model_name = activerecord_model_name(line)
          if model_name.nil?
            log_message :warn, "Unable to find model name in #{line}"
            model_attrs = [] # don't include anything from this model
          end
          break
        end
      end
      log_message :info, "Adding #{model_attrs.count} attributes as pins"
      model_attrs.map do |attr|
        Solargraph::Pin::Method.new(
          name: attr[:name],
          comments: "@return [#{type_translation[attr[:type]]}]",
          location: attr[:location],
          closure: Solargraph::Pin::Namespace.new(name: model_name),
          scope: :instance,
          attribute: true
        )
      end
    end

    def skip_line?(line)
      skip = line.strip.empty? || line =~ /Schema/ || line =~ /Table/ || line =~ /^\s*#\s*$/ || line =~ /frozen string literal/
      log_message :info, 'skipping' if skip
      skip
    end

    def is_comment?(line)
      line =~ (/^\s*#/)
    end

    def col_with_type(line)
      line
        .gsub(/#\s*/, '')
        .split
        .first(2)
    end

    def activerecord_model_name(line)
      line.gsub(/#\s*/, '').match /class\s*?([A-Z]\w+)\s*<\s*(?:ActiveRecord::Base|ApplicationRecord)/
      $1
    end

    # log_message both to STDOUT and Solargraph logger while I am debugging from console
    # and client
    def log_message(level, msg)
      puts "[#{level}] #{msg}"
      Solargraph::Logging.logger.send(level, msg)
    end

    def type_translation
      {
        decimal: 'Decimal',
        integer: 'Int',
        date: 'Date',
        datetime: 'DateTime',
        string: 'String',
        boolean: 'Bool'
      }
    end
  end
end
