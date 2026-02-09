# Vivado batch programming script.
# Usage:
#   vivado -mode batch -source scripts/program_fpga.tcl -tclargs <bitfile>
#
# If no bitfile is provided, the script tries the default build output.

proc pick_bitfile {args} {
    if {[llength $args] > 0} {
        set arg0 [lindex $args 0]
        if {$arg0 ne ""} {
            return $arg0
        }
    }
    set script_dir [file dirname [info script]]
    set root_dir [file normalize [file join $script_dir ".."]]
    set default_glob [file join $root_dir "build" "vivado" "fpga_dnn_inference.runs" "impl_1" "*.bit"]
    set matches [glob -nocomplain $default_glob]
    if {[llength $matches] == 0} {
        puts "ERROR: No bitfile found at $default_glob"
        exit 1
    }
    # Pick newest bitfile by mtime
    set newest [lindex $matches 0]
    set newest_mtime [file mtime $newest]
    foreach f $matches {
        set m [file mtime $f]
        if {$m > $newest_mtime} {
            set newest $f
            set newest_mtime $m
        }
    }
    return $newest
}

set bitfile [pick_bitfile $argv]
if {$bitfile eq ""} {
    puts "ERROR: No bitfile resolved. Provide a path with -tclargs."
    exit 1
}
puts "Programming bitfile: $bitfile"

open_hw_manager
connect_hw_server

set dev ""
set attempts 0
while {$attempts < 3} {
    incr attempts
    if {[catch {open_hw_target}]} {
        # fall through to retry
    } else {
        catch {refresh_hw_target}
        set dev [lindex [get_hw_devices] 0]
        if {$dev ne ""} {
            break
        }
        # If target opened but no devices, try re-registering hw_server
        catch {disconnect_hw_server}
        catch {connect_hw_server}
    }
}

if {$dev eq ""} {
    puts "ERROR: No hardware devices found."
    exit 1
}
current_hw_device $dev
set_property PROGRAM.FILE $bitfile $dev
program_hw_devices $dev
puts "Programming complete."
quit
