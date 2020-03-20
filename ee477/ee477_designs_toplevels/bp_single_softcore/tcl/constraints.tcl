# constraints.tcl
#
# This file is where design timing constraints are defined for dc and
# icc. There are multiple files in toplevels/common that define helper
# functions for setting up complex timing constraints and block constraints
# for components such ass bsg_comm_link, bsg_tag and bsg_clk_gen.
#

create_clock -name core_clk -period 7.0 [get_ports clk_i]
set_clock_uncertainty 1.0 [get_clocks core_clk]
set_input_delay  0.1 -clock core_clk [all_inputs]
set_output_delay 0.1 -clock core_clk [all_outputs]

