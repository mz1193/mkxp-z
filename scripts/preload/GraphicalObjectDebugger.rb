# Graphical Object Global Reference
# v 2.0
# A debugger script.

# Only run if debug mode is on
# $DEBUG is used by XP, $TEST is used by VX and Ace
if $DEBUG || $TEST
	
	# Created to help located graphical objects that are discarded without being disposed
	# A heavily modified version of Mithran's script, found at
	# https://forums.rpgmakerweb.com/index.php?threads/hidden-game-exe-crash-debugger-graphical-object-global-reference-ace.17400/
	
	# Creates a global reference list to all graphical objects by object id.
	# Upon being garbage collected without first being disposed, it then
	# optionally logs information about the object to either the console or a file
	# on the next call to Graphics.update.
	# Graphics.update is used to not log objects that are GC'd during game shutdown.
	
	# Objects may be exempted, if you wish, by calling 'gobj_exempt' on them.
	
	GOBJ_NOTIFY_LEAK = true # when true, displays a list of undisposed graphical objects
	# that have just been garbage collected. The list displays their type and the scene they were created in
	
	GOBJ_DEBUG_FILE = true # makes a file (gobj.txt) in the game directory containing
	# information about undisposed objects when they are garbage collected.
	# the list includes: 
	# the time the error was recorded
	# the object's class
	# the scene it was created during (NilClass = in a script before any scene was created)
	# and the 'caller', or the list of methods run prior to this object's creation
	# the first line on caller will generally be the location of where the 
	# offending object was initially CREATED
	# HOWEVER, the error this script addresses is that this object is never DISPOSED
	# of properly.  Knowing where the object will only allow a scripter to go back
	# and properly dispose of the object at the correct time.
	
	GOBJ_ABRIDGED_LOG = false
	# logs only the basic info about the created object and not the whole stack
	
	GOBJ_ALLOW_VIEWPORT_DISPOSAL = true
	# XP games automatically dispose all objects that are attached to a viewport
	# when the viewport is disposed. Set this constant to false if you would prefer to
	# dispose of them yourself, and therefore wish to be notified if an object is
	# garbage collected without manual disposal
	
	GOBJ_IGNORE_HIDDEN = true
	# Ignore undisposed objects that aren't receiving draw calls
	
	# --- End Setup
	
	if GOBJ_NOTIFY_LEAK || GOBJ_DEBUG_FILE
		
		$gobj = {}
		$gobj_queue = []
		$gobj_viewport = nil
		if ($DEBUG && GOBJ_ALLOW_VIEWPORT_DISPOSAL) || GOBJ_IGNORE_HIDDEN
			$gobj_viewport = {}
		end
		
		[Sprite, Plane, Window, Tilemap].each { |cl|
			cl.class_eval {
				alias dispose_gobj dispose unless method_defined?(:dispose_gobj)
				alias opacity_gobj opacity= unless method_defined?(:opacity_gobj) || !method_defined?(:opacity=)
				alias initialize_gobj initialize unless method_defined?(:initialize_gobj)
				def initialize(*args)
					ret = initialize_gobj(*args)
					scene = nil.class
					begin
						if Object.const_defined?("SceneManager") # Just Ace, I think
							scene = SceneManager.scene.class
						elsif $scene # XP and VX, I think
							scene = $scene.class
						end
					rescue Exception
					end
					o = {
					        "oid" => self.object_id,     # object_id
					        "scene" => scene,            # The active scene
					        "caller" => nil,             # caller list
					        "vpid" => nil,               # viewport.object_id (Used by XP for disposals),
					        "time" => Time.now,          # creation time
					        "class" => self.class.name,  # Class name
					        "oVis" => self.visible,      # object.visible
					        "vpVis" => true,             # viewport.visible
					        "opacity" => true            # object.opacity
					    }
					if GOBJ_ABRIDGED_LOG
						o["caller"] = caller[0..0] if GOBJ_DEBUG_FILE # add caller list if debug file is enabled
					else
						o["caller"] = caller if GOBJ_DEBUG_FILE # add caller list if debug file is enabled
					end
					# if object is disposed already during initialization, dont add it
					unless self.disposed?
						if $gobj_viewport && self.class.method_defined?(:viewport) && self.viewport
							vp = self.viewport
							o["vpid"] = vp.object_id
							o["vpVis"] = !self.viewport.disposed?() && self.viewport.visible
							if !vp.disposed?()
								vpHash = ($gobj_viewport[o["vpid"]] ||= {})
								vpHash[o["oid"]] = nil
							end
						end
						$gobj[self.object_id] = o
						ObjectSpace.define_finalizer(self, Kernel.method(:gobj_process_finalizer))
					end
					ret
				end
				def dispose
					gobj_exempt   # remove from global reference
					dispose_gobj # original dispose
				end
				
				if GOBJ_IGNORE_HIDDEN
					alias visible_gobj visible= unless method_defined?(:visible_gobj)
					def visible=(*args)
						visible_gobj(*args)
						oid = self.object_id
						o = $gobj[oid]
						if o
							o["oVis"] = self.visible
						end
					end
				end
				
				if GOBJ_IGNORE_HIDDEN
					if method_defined?(:opacity=)
						def opacity=(*args)
							opacity_gobj(*args)
							o = $gobj[self.object_id]
								if o
									o["opacity"] = self.opacity > 0
								end
						end
					end
				end
				
				def gobj_exempt
					o = $gobj[self.object_id]
					if o
						if $gobj_viewport && o["vpid"]
							vp = $gobj_viewport[o["vpid"]]
							if vp
								vp.delete(self.object_id)
							end
						end
						$gobj.delete(self.object_id)
					end
				end
				
				if method_defined?(:viewport=) && $gobj_viewport
					alias viewport_gobj viewport= unless method_defined?(:viewport_gobj)
					def viewport=(*args)
						ret = viewport_gobj(*args)
						vp = self.viewport
						oid = self.object_id
						o = $gobj
						if o
							if $gobj_viewport.include?(o["vpid"])
								$gobj_viewport[o["vpid"]].delete(oid)
							end
							if vp
								vpHash = ($gobj_viewport[vp.object_id] ||= {})
								o["vpid"] = vp.object_id
								if !vp.disposed?()
									o["vpVis"] = vp.visible
									vpHash[oid] = nil
								else
									o["vpVis"] = false
								end
							else
								o["vpid"] = nil
								o["vpVis"] = true
							end
						end
						return ret
					end
				end
			} # class eval
		} # each class
		
		class << Graphics
			alias update_gobj update unless method_defined?(:update_gobj)
			def update
				begin
					if $gobj_queue.size > 0
						gobjq = $gobj_queue
						$gobj_queue = []
						if GOBJ_NOTIFY_LEAK
							System.puts "Undisposed graphical objects garbage collected: #{gobjq.collect { |o| [o["class"], o["scene"]] }}"
						end
						if GOBJ_DEBUG_FILE
							gobjq.each{|o|
								gobj_log_to_file(o)
							}
						end
					end
				rescue Exception
				end
				update_gobj
			end
		end
		
		module Kernel
			def gobj_process_finalizer(oid)
				o = $gobj[oid]
				if o
					# Queue object for notifying and logging on the next Graphics.update call
					if !GOBJ_IGNORE_HIDDEN || (o["oVis"] && o["vpVis"] && o["opacity"])
						$gobj_queue.push(o)
					end
					if $gobj_viewport && o["vpid"]
						vp = $gobj_viewport[o["vpid"]]
						if vp
							vp.delete(oid)
						end
					end
					$gobj.delete(oid)
				end
			end
			def gobj_log_to_file(o)
				File.open("gobj.txt", "a") { |f|
					f.print "\n-----\n"
					f.print("Time: #{o["time"]}\n")
					f.print("Memory Leak #{o["class"]}\n")
					f.print("In Scene #{o["scene"]}\n")
					f.print("Creation #{GOBJ_ABRIDGED_LOG ? 'Point' : 'Stack' }:: \n")
					o["caller"].each { |e| e.gsub!(/^\{(\d+)\}\:(\d+)/i) { |m| 
						"Script #{$1} -- #{ScriptNames[$1.to_i]}, Line: #{$2}" }
					} # close o[2].each
					outp = o["caller"].join("\n")
					f.print(outp)
				} # close file
			end
		end
		
		ScriptNames = {}
		
		if $gobj_viewport
			class Viewport
				alias dispose_gobj dispose unless method_defined?(:dispose_gobj)
				def dispose
					vid = self.object_id
					if $DEBUG && GOBJ_ALLOW_VIEWPORT_DISPOSAL
						vpHash = $gobj_viewport[vid]
						if vpHash
							vpHash.keys { |oid|
								$gobj.delete(oid)
							}
							$gobj_viewport.delete(vid)
						end
					elsif GOBJ_IGNORE_HIDDEN
						vpHash = $gobj_viewport[vid]
						if vpHash
							vpHash.keys { |oid|
								$gobj[oid]["vpVis"] = false
							}
							$gobj_viewport.delete(vid)
						end
					end
					
					dispose_gobj
				end
				if GOBJ_IGNORE_HIDDEN
					alias visible_gobj visible= unless method_defined?(:visible_gobj)
					def visible=(*args)
						visible_gobj(*args)
						return if disposed?
						vis = self.visible
						vpHash = $gobj_viewport[self.object_id]
						if vpHash
							vpHash.keys { |oid|
								o = $gobj[oid]
								if o
									o["vpVis"] = vis
								else
									vpHash.delete(oid)
								end
							}
						end
					end
				end
			end
		end
	
		$RGSS_SCRIPTS.each_with_index { |s, i| ScriptNames[i] = s[1] } 
	end
end
