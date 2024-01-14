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
	
	# --- End Setup
	
	if GOBJ_NOTIFY_LEAK || GOBJ_DEBUG_FILE
		
		$gobj = []
		$gobj_queue = []
		
		[Sprite, Plane, Window, Tilemap].each { |cl|
			class << cl
				alias new_gobj new unless method_defined?(:new_gobj)
				def new(*args)
					obj = new_gobj(*args)
					# #0: object_id,
					# #1: The active scene
					# #2: caller list,
					# #3: viewport.object_id (Used by XP for disposals),
					# #4: creation time,
					# #5: Class name
					scene = nil.class
					begin
						if Object.const_defined?("SceneManager") # Just Ace, I think
							scene = SceneManager.scene.class
						elsif $scene # XP and VX, I think
							scene = $scene.class
						end
					rescue Exception
					end
					ary = [obj.object_id, scene, nil, nil, Time.now, self.name]
					if GOBJ_ABRIDGED_LOG
						ary[2] = (caller[0..0]) if GOBJ_DEBUG_FILE # add caller list if debug file is enabled
					else
						ary[2] = (caller) if GOBJ_DEBUG_FILE # add caller list if debug file is enabled      
					end
					# if object is disposed already during initialization, dont add it
					unless obj.disposed? 
						if $DEBUG && GOBJ_ALLOW_VIEWPORT_DISPOSAL && obj.method_defined?(:viewport) && obj.method_defined?(:viewport=)
							ary[3] = obj.viewport.object_id
						end
						$gobj.push(ary) 
						ObjectSpace.define_finalizer(obj, Kernel.method(:gobj_process_finalizer))
					end
					obj
				end
				
			end
			
			cl.class_eval {
				alias dispose_gobj dispose unless method_defined?(:dispose_gobj)
				def dispose
					gobj_exempt   # remove from global reference
					dispose_gobj # original dispose
				end
				
				def gobj_exempt
					$gobj.delete_if { |a| a[0] == self.object_id } 
				end
				
				if $DEBUG && GOBJ_ALLOW_VIEWPORT_DISPOSAL && method_defined?(:viewport) && method_defined?(:viewport=)
					alias viewport_gobj viewport= unless method_defined?(:viewport_gobj)
					def viewport=(*args)
						ret = viewport_gobj(*args)
						vp = viewport
						if vp && !vp.disposed?
							ary[3] = viewport.object_id
						else
							ary[3] = nil
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
						gobjs = $gobj_queue
						$gobj_queue = []
						if GOBJ_NOTIFY_LEAK
							System.puts "Undisposed graphical objects garbage collected: #{gobjs.collect { |o| [o[5], o[1]] }}"
						end
						if GOBJ_DEBUG_FILE
							gobjs.each{|o|
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
			def gobj_process_finalizer(id)
				ind = $gobj.index{|o| o[0] == id }
				if ind
					# Queue object for notifying and logging on the next Graphics.update call
					$gobj_queue.push($gobj[ind])
					$gobj.delete_at(ind)
				end
			end
			def gobj_log_to_file(o)
				File.open("gobj.txt", "a") { |f|
					f.print "\n-----\n"
					f.print("Time: #{o[4]}\n")
					f.print("Memory Leak #{o[5]}\n")
					f.print("In Scene #{o[1]}\n")
					f.print("Creation #{GOBJ_ABRIDGED_LOG ? 'Point' : 'Stack' }:: \n")
					o[2].each { |e| e.gsub!(/^\{(\d+)\}\:(\d+)/i) { |m| 
						"Script #{$1} -- #{ScriptNames[$1.to_i]}, Line: #{$2}" }
					} # close o[2].each
					outp = o[2].join("\n")
					f.print(outp)
				} # close file
			end
		end
		
		ScriptNames = {}
		
		if $DEBUG && GOBJ_ALLOW_VIEWPORT_DISPOSAL
			class Viewport
				alias dispose_gobj dispose unless method_defined?(:dispose_gobj)
				def dispose
					$gobj.delete_if { |o|
						o[3] == self.object_id
					}
				end
			end
		end
	
		$RGSS_SCRIPTS.each_with_index { |s, i| ScriptNames[i] = s[1] } 
	end
end
