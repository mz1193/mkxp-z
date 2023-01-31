# mkxp_wrap.rb
# Author: Splendide Imaginarius (2022)

# Creative Commons CC0: To the extent possible under law, Splendide Imaginarius
# has waived all copyright and related or neighboring rights to mkxp_wrap.rb.
# https://creativecommons.org/publicdomain/zero/1.0/

# This preload script provides functions that existed in Ancurio's mkxp, but
# were renamed in mkxp-z, so that games (or other preload scripts) that expect
# Ancurio's function names can find them.

module MKXP
	def data_directory(*args)
		System::data_directory(*args)
	end

	def puts(*args)
		System::puts(*args)
	end

	def raw_key_states(*args)
		Input::raw_key_states(*args)
	end

	def mouse_in_window(*args)
		Input::mouse_in_window(*args)
	end
end
