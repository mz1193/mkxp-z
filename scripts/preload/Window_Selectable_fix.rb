# encoding: UTF-8

# This thing is hideous and I take no credit for it.
# CC0 license. Go wild.

$max_tex_size = Bitmap.respond_to?(:max_size) ? Bitmap.max_size() : Float::INFINITY

module Window_Selectable_Patcher
  # Hacks in support for Window_Selectable instances with arbitrary heights.
  # I'm not bothering with width. That case is extremely niche.
	
	# Define :contents_height in :initialize, so it can be done during preloading
	def initialize(*args)
		# Silence the warning from removing this initialize method
		old_stderr = $stderr
		$stderr = StringIO.new
		Window_Selectable_Patcher.send(:remove_method,:initialize)
		$stderr = old_stderr
		
		Window_Selectable.send(:define_method, :contents_height){
			base = [super() - super() % item_height, row_max * item_height].max
			unless $max_tex_size.is_a?(Integer)
				base
			else
				[$max_tex_size - $max_tex_size % item_height, base].min
			end
		}
		
		super
	end
	
	module Patch_Window
			@offset ||= 0
			def oy
				@real_oy || super
			end
			def oy=(val)
				@real_oy = val
				return super(val - @offset)
			end
			module Patch_cursor_rect
				def set(*args)
					super
					self.y -= @offset
				end
				def y
					super + @offset
				end
				def y=(val)
					super(val - @offset)
				end
			end
			def update_cursor_rect
				realY = cursor_rect.y
				class << cursor_rect
					include Patch_cursor_rect
				end
				cursor_rect.instance_variable_set("@offset", @offset)
				cursor_rect.y = realY
			end
			def cursor_rect=(*args)
				super
				update_cursor_rect
			end
	end
	
	class MegaBitmapWrapper
	
		BITMAP_METHODS = [
							:font, :font=, :width, :height, :rect,
							:blt, :stretch_blt, :clear_rect, :fill_rect,
							:gradient_fill_rect, :draw_text, :get_pixel, :set_pixel
						 ]
		
		FONT_METHODS = [:bold=, :color=, :italic=, :name=, :out_color=, :outline=, :shadow=, :size=]
		
		COLOR_METHODS = [
							:alpha, :blue, :green, :red,
							:alpha=, :blue=, :green=, :red=,
							:set
						]
		
		module MegaFont
			def method_redirect(method, *args)
				if @instance_methods.include?(method)
					ret = nil
					@fonts.each {|font|
						val = @instance_methods[method].bind(font).call(*args)
						ret = val if font.equal?(self)
					}
					return ret
				end
			end
		end
		
		module MegaWindow
			def oy=(val)
				if @MegaBitmap
					oldContents = self.contents
					@offset = @MegaBitmap.updateContent(val)
					if self.contents != oldContents
						 self.update_cursor_rect
					end
				end
				return super
			end
		end
		
		module MegaBitmap
			def call_single_bitmap_method(method, *args)
				@instance_methods[method].bind(self).call(*args)
			end
			
			def call_mega_bitmap_method(method, *args)
				ret = nil
				@bitmaps.each {|bitmap|
					val = bitmap.call_single_bitmap_method(method, *args)
					ret = val if bitmap.equal?(self)
				}
				return ret
			end
			def modify_rect(method, *args)
				ret = nil
				if args[0].is_a?(Rect)
					@bitmaps.each{|bitmap|
						offset = @MegaBitmap.getOffset(bitmap)
						rng = Range.new(offset, offset + bitmap.height)
						newArgs = args.dup
						rect = newArgs[0] = args[0].dup
						if rng.cover?(rect.y) || rng.cover?(rect.y + rect.height)
							rect.y -= offset
							val = bitmap.call_single_bitmap_method(method, *newArgs)
							ret = val if bitmap.equal?(self)
						end
					}
				elsif args[1].is_a?(Numeric) && args[3].is_a?(Numeric)
					@bitmaps.each{|bitmap|
						offset = @MegaBitmap.getOffset(bitmap)
						rng = Range.new(offset, offset + bitmap.height)
						if rng.cover?(args[1]) || rng.cover?(args[1] + args[3])
							newArgs = args.dup
							newArgs[1] -= offset
							val = bitmap.call_single_bitmap_method(method, *newArgs)
							ret = val if bitmap.equal?(self)
						end
					}
				end
				return ret
			end
			def modify_pixel(method, *args)
				@bitmaps.each{|bitmap|
					offset = @MegaBitmap.getOffset(bitmap)
					rng = Range.new(offset, offset + bitmap.height)
					if rng.cover?(args[1])
						return call_single_bitmap_method(method, *args)
					end
				}
			end
			def modify_blt(method, *args)
				ret = nil
				if args[0].is_a?(Rect)
					y = args[0].y
					height = args[0].height
				else
					y = args[1]
					height = args[3].height
				end
				@bitmaps.each{|bitmap|
					offset = @MegaBitmap.getOffset(bitmap)
					rng = Range.new(offset, offset + bitmap.height)
					if rng.cover?(y) || rng.cover?(y + height)
						newArgs = args.dup
						if args[0].is_a?(Rect)
							newArgs[0] = args[0].dup
							newArgs[0].y = y - offset
						else
							newArgs[1] = y - offset
						end
						val = bitmap.call_single_bitmap_method(method, *newArgs)
						ret = val if bitmap.equal?(self)
					end
				}
			end
			def method_redirect(method, *args)
				if @instance_methods.include?(method)
					case method
					when :font, :width, :height
						return call_single_bitmap_method(method, *args)
					when :font=
						return call_mega_bitmap_method(method, *args)
					when :rect
						rect = call_single_bitmap_method(method, *args).dup
						rect.width = @width
						rect.height = @height
						return rect
					when :blt, :stretch_blt
						return modify_blt(method, *args)
					when :clear_rect, :fill_rect, :gradient_fill_rect, :draw_text
						return modify_rect(method, *args)
					when :get_pixel, :set_pixel
						return modify_pixel(method, *args)
					else
						return call_single_bitmap_method(method, *args)
					end
				end
			end
		end
		
		def pre_include_mod(object)
				instance_methods = {}
				
				const_arr = [BITMAP_METHODS, FONT_METHODS, COLOR_METHODS]
				methods_arr = const_arr[[Bitmap, Font, Color].find_index{|c| object.is_a?(c)}]
				
				methods_arr.each{ |method|
					instance_methods[method] = object.method(method).unbind
					object.singleton_class.send(:define_method, method){ |*args|
						method_redirect(method, *args)
					}
				}
				
				object.instance_variable_set("@instance_methods",instance_methods)
		end
		def self.new(*args, &block)
			allocate.send(:initialize, *args, &block);
		end
		def initialize(width, height, window)
			@window = window
			@bitmaps = []
			@fonts = []
			@fonts_color = []
			@fonts_out_color = []
			@width = width
			@height = height
			# @buffer needs to be at least the size of window.height
			@buffer = window.height
			@offset = 0
			@index = 0
			while height > 0
				bitmapHeight = [height, $max_tex_size].min
				if height != bitmapHeight
					height += @buffer
				end
				lastBitmap = Bitmap.new(width, bitmapHeight)
				@bitmaps.push(lastBitmap)
				lastFont = lastBitmap.font
				@fonts.push(lastFont)
				lastFont.instance_variable_set("@fonts",@fonts)
				
				lastFont_color = lastFont.color
				@fonts_color.push(lastFont_color)
				lastFont_color.instance_variable_set("@fonts",@fonts_color)
				pre_include_mod(lastFont.color)
				class << lastFont.color
					include MegaFont
				end
				
				lastFont_out_color = lastFont.out_color
				@fonts_out_color.push(lastFont_out_color)
				lastFont_out_color.instance_variable_set("@fonts",@fonts_out_color)
				pre_include_mod(lastFont.out_color)
				class << lastFont.out_color
					include MegaFont
				end
				
				pre_include_mod(lastFont)
				class << lastFont
					include MegaFont
				end
				lastBitmap.instance_variable_set("@bitmaps",@bitmaps)
				lastBitmap.instance_variable_set("@MegaBitmap",self)
				pre_include_mod(lastBitmap)
				class << lastBitmap
					include MegaBitmap
				end
				height -= bitmapHeight
			end
			
			window.instance_variable_set("@MegaBitmap",self)
			class << window
				include MegaWindow
			end
			return @bitmaps[0]
		end
		def getOffset(bitmap)
			[@bitmaps.index(bitmap) * ($max_tex_size - @buffer), 0].max
		end
		def updateContent(oy)
			oldOffset = @offset
			if oy < @offset
				@index -= 1
				@index = 0 if @index < 0
				return @offset unless @bitmaps[@index]
				@window.contents = @bitmaps[@index]
			elsif oy + (@window.height - @window.padding_bottom) > @offset + @bitmaps[@index].height
				@index += 1
				@index = @bitmaps.size - 1 if @index >= @bitmaps.size
				return @offset unless @bitmaps[@index]
				@window.contents = @bitmaps[@index]
			else
				return @offset
			end
			newOffset = getOffset(@bitmaps[@index])
			@offset = newOffset > 0 ? newOffset : 0
			if oldOffset != @offset
				updateContent(oy)
			end
			return @offset
		end
	end
	
	def create_contents
		super
		
		@MegaBitmap = nil
		max_tex_size = $max_tex_size
		$max_tex_size = nil
		full_height = contents_height
		$max_tex_size = max_tex_size
		if $max_tex_size.is_a?(Integer) && full_height > $max_tex_size && contents_width > 0
			class << self
				include Patch_Window
			end
			width = contents.width
			contents.dispose
			self.contents = MegaBitmapWrapper.new(width, full_height, self)
			@offset = 0
			update_cursor_rect
			return
		end
	end
end


class Window_Selectable < Window_Base
	include Window_Selectable_Patcher
end
