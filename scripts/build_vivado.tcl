# Vivado batch build
set proj_name fpga_dnn_inference
set proj_dir "build/vivado"
set part_name "xc7a200tsbg484-1"

file mkdir $proj_dir

create_project -force $proj_name $proj_dir -part $part_name

set vhdl_files [glob -nocomplain -directory rtl -types f -recursive *.vhd]
if {[llength $vhdl_files] > 0} {
    add_files -norecurse $vhdl_files
}

add_files -fileset constrs_1 constraints/nexys_video.xdc

set_property top top_nexys_video [current_fileset]

launch_runs synth_1
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1

puts "Build completed: $proj_dir"
