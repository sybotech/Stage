#!/usr/bin/tclsh

#
# A simple program to convert from Stage 1.1 worldfiles to Stage 1.2
# worldfiles.  It's far from perfect, and will likely barf on invalid
# or nonstandard syntax, but it should work most of the time.
#
#     Brian Gerkey (gerkey@robotics.usc.edu)
#

set USAGE "Usage: worldfileconv.tcl <worldfile>"

if {$argc != 1} {
  puts $USAGE
  exit -1
}

set fname [lindex $argv 0]

if {![string compare [file extension $fname] ".m4"]} {
  exec m4 $fname > [file rootname $fname]
  set fname [file rootname $fname]
}

set fd [open $fname r]

set envfile ""
set scale ""
set unit_length ""
set unit_angle ""

set parent_stack {-1}
set potential_parent ""

array set devices {}
set i 0

while {![eof $fd]} {
  set line [string trimleft [gets $fd]]

  if {![string length $line] ||
       [string index $line 0] == "\#"} {
    continue
  } elseif {[string index $line 0] == "\{"} {
    lappend parent_stack $potential_parent
  } elseif {[string index $line 0] == "\}"} {
    set parent_stack [lrange $parent_stack 0 end-1]
  } elseif {![string compare [lindex $line 0] "set"]} {
    if {![string compare [lindex $line 1] "environment_file"]} {
      set envfile [lindex $line 3]
      # assume that we need to add the .gz
      if {[string compare [lindex [split $envfile .] end] "gz"]} {
        set envfile "${envfile}.gz"
      }
    } elseif {![string compare [lindex $line 1] "pixels_per_meter"]} {
      set scale [expr 1.0 / [lindex $line 3]]
    } elseif {![string compare [lindex $line 1] "angles"]} {
      set unit_angle [lindex $line 3]
    } elseif {![string compare [lindex $line 1] "units"]} {
      set unit_length [lindex $line 3]
    } else {
      puts stderr "Warning: ignoring set statement:\n  $line"
    }
  } elseif {![string compare [lindex $line 0] "create"]} {
    if {![string compare [lindex [split [lindex $line 1] _] 1] "device"]} {
      set devices($i,name) [lindex [split [lindex $line 1] _] 0]
    } else {
      set devices($i,name) [lindex $line 1]
    }
    set devices($i,parent,[lindex $parent_stack end]) 0
    set potential_parent $i

    set j 2
    while {$j < [llength $line]} {
      if {![string compare [lindex $line $j] "pose"]} {
        incr j
        set x [lindex $line $j]
        if {$x == ""} {set x 0.0}
        incr j
        set y [lindex $line $j]
        if {$y == ""} {set y 0.0}
        incr j
        set th [lindex $line $j]
        if {$th == ""} {set th 0.0}
        set devices($i,params,pose) "\[$x $y $th\]"
      } elseif {![string compare [lindex $line $j] "size"]} {
        incr j
        set x [lindex $line $j]
        if {$x == ""} {set x 0.0}
        incr j
        set y [lindex $line $j]
        if {$y == ""} {set y 0.0}
        set devices($i,params,size) "\[$x $y\]"
      } else {
        set name [lindex $line $j]
        incr j
        set value [lindex $line $j]
        if {[catch {expr $value + 1}]} {
          # couldn't add to it, so assume it's a string
          set devices($i,params,$name) "\"$value\""
        } else {
          set devices($i,params,$name) $value
        }
      }
      incr j
    }

    incr i
  }
}

#parray devices

set indent_space "  "
# recursive proc to unroll devs
proc output_devs {devlist indent_level} {
  global indent_space devices
  foreach dev $devlist {
    set id [lindex [split $dev ,] 0]
    puts -nonewline [string repeat $indent_space $indent_level]
    puts -nonewline $devices($id,name)
    set childlist [array names devices *,parent,$id]
    if {![llength $childlist]} {
      puts -nonewline " ( "
    } else {
      puts "\n[string repeat $indent_space $indent_level]("
      puts -nonewline "[string repeat $indent_space [expr $indent_level + 1]]"
    }
    foreach paramname [array names devices $id,params,*] {
      set name [lindex [split $paramname ,] 2]
      puts -nonewline "$name $devices($paramname) "
    }
    if {![llength $childlist]} {
      puts ")\n"
    } else {
      puts ""
      output_devs $childlist [expr $indent_level + 1]
      puts "[string repeat $indent_space $indent_level])\n"
    }
  }
}

# a header
puts "# This file autogenerated by the Stage worldfile converter\n"

# output environment stuff first
puts "environment\n("
puts "$indent_space file \"$envfile\""
puts "$indent_space scale $scale"
puts "$indent_space resolution $scale"
puts ")\n"

if {$unit_length != ""} {puts "unit_length \"$unit_length\""}
if {$unit_angle != ""} {puts "unit_angle \"$unit_angle\"\n"}

# start with top-level entities
output_devs [array names devices *,parent,-1] 0

