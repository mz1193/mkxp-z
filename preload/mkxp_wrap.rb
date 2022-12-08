# mkxp_wrap.rb
#
# This file is part of mkxp-z.
#
# Copyright (C) 2022 Splendide Imaginarius
#
# mkxp-z is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# mkxp-z is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with mkxp-z.  If not, see <http://www.gnu.org/licenses/>.

# This preload script provides functions that existed in Ancurio's mkxp, but
# were renamed in mkxp-z, so that games (or other preload scripts) that expect
# Ancurio's function names can find them. Use it via the "preloadScript" option
# in mkxp.json.

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
