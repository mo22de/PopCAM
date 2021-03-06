require_relative './models/board'
require_relative './models/component'
require_relative './exceptions/invalid_file_exception'
require_relative './exceptions/brd_parsing_exception'

class BrdParser

  attr_reader :board
  delegate :libraries, :components, :to => :board

  def self.parse(brd_file)
    BrdParser.new(brd_file).parse
  end

  def initialize(brd_file)
    @brd_file = brd_file
    @board = Board.new
  end

  def parse
    f = File.open(@brd_file)
    @doc = Nokogiri::XML(f)
    if @doc.css('libraries').blank?
      msg =  "PopCAM does not support legacy .brd files. "
      msg += "Please ugrade to Eagle 6 and re-save board."
      raise InvalidFileException.new msg
    end
    parse_libraries
    parse_components
    f.close
    return board
  end

  # Loading the package libraries (each package is a specific type of component)
  # Packages are keyed by [library_name][package_name]
  def parse_libraries
    board.libraries = {}
    @doc.css('libraries library').each do |lib_el|
      # Adding the library
      lib_name = lib_el.attr(:name)
      libraries[lib_name.to_sym] = lib = {}
      # Adding the packages inside the library
      lib_el.css('package').each do |pkg_el|
        # Adding the package
        pkg_name = pkg_el.attr(:name).to_sym
        layer_id = pkg_el.css('smd')[0][:layer]
        layer_name = @doc.css("layers layer[number=\"#{layer_id}\"]")[0][:name]
        lib[pkg_name] = {
          name: "#{lib_name}::#{pkg_name}",
          pads: pkg_el.css('smd').map {|el| parse_pads el },
          layer: layer_name.to_sym
        }
        # ap lib[pkg_name]
      end
    end
  end

  # Parsing the individual smd pads of the package
  def parse_pads(el)
    attrs = {}
    el.attributes.slice(*%w(x y dx dy)).each do |k, v|
      attrs[k.to_sym] = v.value.to_f
    end
    attrs[:relative_rotation] = parse_rot(el)
    return attrs
  end

  def parse_components
    # Loading individual components (things on the board / instances of packages)
    board.components = @doc.css('board elements element').map do |el|
      library = libraries[el.attr("library").to_sym]
      error = "Library not found: #{el.attr("library")}" unless library.present?
      package = library[el.attr("package").to_sym]
      error = "Package not found: #{el.attr("package")}" unless package.present?
      raise BrdParsingException.new error if error.present?
      device_name = [package[:name], el[:value]].reject {|s| s.blank?}
      .join("::").to_sym
      # ap el.attr("rot")
      Component.new(
        name: el[:name],
        device_name: device_name,
        package: package,
        relative_x: el.attr("x").to_f,
        relative_y: el.attr("y").to_f,
        relative_rotation: parse_rot(el),
        mirrored: parse_mirrored(el),
        parent: board
      )
    end
  end

  def mark_as_dirty!
    super
    components.each &:mark_as_dirty!
  end

  private

  def parse_rot(el)
    (el.attr("rot")||"R0")[/[0-9]+/].to_f
  end

  def parse_mirrored(el)
    (el.attr("rot")||"").include? "M"
  end
end