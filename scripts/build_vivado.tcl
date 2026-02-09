# Vivado batch build
set script_dir [file dirname [info script]]
set root_dir [file normalize [file join $script_dir ".."]]
set proj_name fpga_dnn_inference
set proj_dir [file join $root_dir "build" "vivado"]
set part_name "xc7a200tsbg484-1"

file mkdir $proj_dir

create_project -force $proj_name $proj_dir -part $part_name

proc collect_files {base pattern} {
    set results {}
    foreach item [glob -nocomplain -directory $base *] {
        if {[file isdirectory $item]} {
            set results [concat $results [collect_files $item $pattern]]
        } else {
            if {[string match $pattern [file tail $item]]} {
                lappend results $item
            }
        }
    }
    return $results
}

set vhdl_files [collect_files [file join $root_dir "rtl"] "*.vhd"]
if {[llength $vhdl_files] > 0} {
    add_files -norecurse $vhdl_files
}

set verilog_files [collect_files [file join $root_dir "rtl" "nn" "generated"] "*.v"]
if {[llength $verilog_files] > 0} {
    add_files -norecurse $verilog_files
}

set_property source_mgmt_mode None [current_project]
set_property include_dirs [file join $root_dir "rtl" "nn" "generated"] [current_fileset]

add_files -fileset constrs_1 [file join $root_dir "constraints" "nexys_video.xdc"]

set_property top top_nexys_video [current_fileset]

launch_runs synth_1
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1

puts "Build completed: $proj_dir"
