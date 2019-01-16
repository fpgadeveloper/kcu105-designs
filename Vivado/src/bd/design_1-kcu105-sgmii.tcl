################################################################
# Block diagram build script
################################################################

# CHECKING IF PROJECT EXISTS
if { [get_projects -quiet] eq "" } {
   puts "ERROR: Please open or create a project!"
   return 1
}

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

create_bd_design $design_name

current_bd_design $design_name

set parentCell [get_bd_cells /]

# Get object for parentCell
set parentObj [get_bd_cells $parentCell]
if { $parentObj == "" } {
   puts "ERROR: Unable to find parent cell <$parentCell>!"
   return
}

# Make sure parentObj is hier blk
set parentType [get_property TYPE $parentObj]
if { $parentType ne "hier" } {
   puts "ERROR: Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."
   return
}

# Save current instance; Restore later
set oldCurInst [current_bd_instance .]

# Set parent object as current
current_bd_instance $parentObj

# Add the Memory controller (MIG) for the DDR4
create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4 ddr4_0

# Connect MIG external interfaces
apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {default_sysclk_300 ( 300 MHz System differential clock ) } Manual_Source {Auto}}  [get_bd_intf_pins ddr4_0/C0_SYS_CLK]
apply_bd_automation -rule xilinx.com:bd_rule:board -config {Board_Interface "ddr4_sdram ( DDR4 SDRAM ) " }  [get_bd_intf_pins ddr4_0/C0_DDR4]
apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {reset ( FPGA Reset ) } Manual_Source {New External Port (ACTIVE_HIGH)}}  [get_bd_pins ddr4_0/sys_rst]

# Add the Microblaze
create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze microblaze_0
# Use 100MHz additional MIG clock (note: using the 300MHz MIG clock would make it hard to close timing and is not necessary)
apply_bd_automation -rule xilinx.com:bd_rule:microblaze -config { axi_intc {1} axi_periph {Enabled} cache {64KB} clk {/ddr4_0/addn_ui_clkout1 (100 MHz)} debug_module {Debug Only} ecc {None} local_mem {64KB} preset {None}}  [get_bd_cells microblaze_0]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {/ddr4_0/addn_ui_clkout1 (100 MHz)} Clk_slave {/ddr4_0/c0_ddr4_ui_clk (300 MHz)} Clk_xbar {Auto} Master {/microblaze_0 (Cached)} Slave {/ddr4_0/C0_DDR4_S_AXI} intc_ip {Auto} master_apm {0}}  [get_bd_intf_pins ddr4_0/C0_DDR4_S_AXI]
apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {reset ( FPGA Reset ) } Manual_Source {New External Port (ACTIVE_LOW)}}  [get_bd_pins rst_ddr4_0_100M/ext_reset_in]

# Configure MicroBlaze for Linux
set_property -dict [list CONFIG.G_TEMPLATE_LIST {4} \
CONFIG.G_USE_EXCEPTIONS {1} \
CONFIG.C_USE_MSR_INSTR {1} \
CONFIG.C_USE_PCMP_INSTR {1} \
CONFIG.C_USE_BARREL {1} \
CONFIG.C_USE_DIV {1} \
CONFIG.C_USE_HW_MUL {2} \
CONFIG.C_UNALIGNED_EXCEPTIONS {1} \
CONFIG.C_ILL_OPCODE_EXCEPTION {1} \
CONFIG.C_M_AXI_I_BUS_EXCEPTION {1} \
CONFIG.C_M_AXI_D_BUS_EXCEPTION {1} \
CONFIG.C_DIV_ZERO_EXCEPTION {1} \
CONFIG.C_PVR {2} \
CONFIG.C_OPCODE_0x0_ILLEGAL {1} \
CONFIG.C_ICACHE_LINE_LEN {8} \
CONFIG.C_ICACHE_VICTIMS {8} \
CONFIG.C_ICACHE_STREAMS {1} \
CONFIG.C_DCACHE_VICTIMS {8} \
CONFIG.C_USE_MMU {3} \
CONFIG.C_MMU_ZONES {2}] [get_bd_cells microblaze_0]

# Clock wizard for the 125MHz system clock
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clk_wiz_0
set_property -dict [list CONFIG.CLK_IN1_BOARD_INTERFACE {sysclk_125} CONFIG.PRIM_SOURCE {Differential_clock_capable_pin}] [get_bd_cells clk_wiz_0]
apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {sysclk_125 ( 125 MHz System differential clock ) } Manual_Source {Auto}}  [get_bd_intf_pins clk_wiz_0/CLK_IN1_D]
apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {Custom} Manual_Source {Auto}}  [get_bd_pins clk_wiz_0/reset]
set_property -dict [list CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125} CONFIG.USE_LOCKED {false} CONFIG.MMCM_DIVCLK_DIVIDE {1} CONFIG.MMCM_CLKOUT0_DIVIDE_F {8.000} CONFIG.CLKOUT1_JITTER {119.348}] [get_bd_cells clk_wiz_0]

# PCS/PMA or SGMII IP
create_bd_cell -type ip -vlnv xilinx.com:ip:gig_ethernet_pcs_pma gig_ethernet_pcs_pma_0
set_property -dict [list CONFIG.ETHERNET_BOARD_INTERFACE {sgmii_lvds} \
CONFIG.DIFFCLK_BOARD_INTERFACE {sgmii_phyclk} \
CONFIG.Standard {SGMII} \
CONFIG.Physical_Interface {LVDS} \
CONFIG.Ext_Management_Interface {true} \
CONFIG.MDIO_BOARD_INTERFACE {mdio_mdc} \
CONFIG.SupportLevel {Include_Shared_Logic_in_Core}] [get_bd_cells gig_ethernet_pcs_pma_0]

# Reset signal for PCS/PMA or SGMII
connect_bd_net [get_bd_ports reset] [get_bd_pins gig_ethernet_pcs_pma_0/reset]

# Automation for PCS/PMA or SGMII
apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {mdio_mdc ( Onboard PHY ) } Manual_Source {Auto}}  [get_bd_intf_pins gig_ethernet_pcs_pma_0/ext_mdio_pcs_pma]
apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {sgmii_lvds ( Onboard PHY ) } Manual_Source {Auto}}  [get_bd_intf_pins gig_ethernet_pcs_pma_0/sgmii]
apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {sgmii_phyclk ( 625 MHz SGMII differential clock from Marvell PHY ) } Manual_Source {Auto}}  [get_bd_intf_pins gig_ethernet_pcs_pma_0/refclk125_in]

# Correct the SGMII PHYCLK frequency to 625MHz
set_property -dict [list CONFIG.LvdsRefClk {625}] [get_bd_cells gig_ethernet_pcs_pma_0]
connect_bd_intf_net [get_bd_intf_ports sgmii_phyclk] [get_bd_intf_pins gig_ethernet_pcs_pma_0/refclk625_in]

# Constant for the PHY address
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant const_phyaddr_0
set_property -dict [list CONFIG.CONST_WIDTH {5} CONFIG.CONST_VAL {0x05}] [get_bd_cells const_phyaddr_0]
connect_bd_net [get_bd_pins const_phyaddr_0/dout] [get_bd_pins gig_ethernet_pcs_pma_0/phyaddr]

# AXI Ethernet IP: Use internal GMII interface to connect with SGMII IP
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_ethernet axi_ethernet_0
set_property -dict [list CONFIG.USE_BOARD_FLOW {false} \
CONFIG.Include_IO {false} \
CONFIG.TXCSUM {Full} \
CONFIG.RXCSUM {Full}] [get_bd_cells axi_ethernet_0]

# Connect AXI Ethernet to SGMII and clocks
connect_bd_intf_net [get_bd_intf_pins axi_ethernet_0/gmii] [get_bd_intf_pins gig_ethernet_pcs_pma_0/gmii_pcs_pma]
connect_bd_intf_net [get_bd_intf_pins axi_ethernet_0/mdio] [get_bd_intf_pins gig_ethernet_pcs_pma_0/mdio_pcs_pma]
connect_bd_net [get_bd_pins ddr4_0/addn_ui_clkout1] [get_bd_pins axi_ethernet_0/s_axi_lite_clk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins axi_ethernet_0/gtx_clk]

# Automation: Connect PHY reset and S_AXI interface
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {/ddr4_0/addn_ui_clkout1 (100 MHz)} Clk_slave {/ddr4_0/addn_ui_clkout1 (100 MHz)} Clk_xbar {/ddr4_0/addn_ui_clkout1 (100 MHz)} Master {/microblaze_0 (Periph)} Slave {/axi_ethernet_0/s_axi} intc_ip {/microblaze_0_axi_periph} master_apm {0}}  [get_bd_intf_pins axi_ethernet_0/s_axi]
apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {phy_reset_out ( Onboard PHY ) } Manual_Source {New External Port (ACTIVE_LOW)}}  [get_bd_pins axi_ethernet_0/phy_rst_n]

# Add the AXI DMA
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma axi_ethernet_0_dma

# DMA Connections
connect_bd_intf_net [get_bd_intf_pins axi_ethernet_0_dma/M_AXIS_MM2S] [get_bd_intf_pins axi_ethernet_0/s_axis_txd]
connect_bd_intf_net [get_bd_intf_pins axi_ethernet_0_dma/M_AXIS_CNTRL] [get_bd_intf_pins axi_ethernet_0/s_axis_txc]
connect_bd_intf_net [get_bd_intf_pins axi_ethernet_0/m_axis_rxd] [get_bd_intf_pins axi_ethernet_0_dma/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins axi_ethernet_0/m_axis_rxs] [get_bd_intf_pins axi_ethernet_0_dma/S_AXIS_STS]

connect_bd_net [get_bd_pins axi_ethernet_0_dma/mm2s_prmry_reset_out_n] [get_bd_pins axi_ethernet_0/axi_txd_arstn]
connect_bd_net [get_bd_pins axi_ethernet_0_dma/mm2s_cntrl_reset_out_n] [get_bd_pins axi_ethernet_0/axi_txc_arstn]
connect_bd_net [get_bd_pins axi_ethernet_0_dma/s2mm_prmry_reset_out_n] [get_bd_pins axi_ethernet_0/axi_rxd_arstn]
connect_bd_net [get_bd_pins axi_ethernet_0_dma/s2mm_sts_reset_out_n] [get_bd_pins axi_ethernet_0/axi_rxs_arstn]

connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins axi_ethernet_0_dma/m_axi_sg_aclk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins axi_ethernet_0_dma/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins axi_ethernet_0_dma/m_axi_s2mm_aclk]

connect_bd_net [get_bd_pins ddr4_0/addn_ui_clkout1] [get_bd_pins axi_ethernet_0_dma/s_axi_lite_aclk]

# Connect interrupts
set_property -dict [list CONFIG.NUM_PORTS {7}] [get_bd_cells microblaze_0_xlconcat]
connect_bd_net [get_bd_pins gig_ethernet_pcs_pma_0/an_interrupt] [get_bd_pins microblaze_0_xlconcat/In0]
connect_bd_net [get_bd_pins axi_ethernet_0/mac_irq] [get_bd_pins microblaze_0_xlconcat/In1]
connect_bd_net [get_bd_pins axi_ethernet_0/interrupt] [get_bd_pins microblaze_0_xlconcat/In2]
connect_bd_net [get_bd_pins axi_ethernet_0_dma/mm2s_introut] [get_bd_pins microblaze_0_xlconcat/In3]
connect_bd_net [get_bd_pins axi_ethernet_0_dma/s2mm_introut] [get_bd_pins microblaze_0_xlconcat/In4]

# No I/O (internal only)
set_property -dict [list CONFIG.Include_IO {false}] [get_bd_cells axi_ethernet_0]

# Automation: AXI-Streaming interfaces
apply_bd_automation -rule xilinx.com:bd_rule:clkrst -config {Clk "/clk_wiz_0/clk_out1 (125 MHz)" }  [get_bd_pins axi_ethernet_0/axis_clk]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {/ddr4_0/addn_ui_clkout1 (100 MHz)} Clk_slave {/ddr4_0/addn_ui_clkout1 (100 MHz)} Clk_xbar {/ddr4_0/addn_ui_clkout1 (100 MHz)} Master {/microblaze_0 (Periph)} Slave {/axi_ethernet_0_dma/S_AXI_LITE} intc_ip {/microblaze_0_axi_periph} master_apm {0}}  [get_bd_intf_pins axi_ethernet_0_dma/S_AXI_LITE]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {/clk_wiz_0/clk_out1 (125 MHz)} Clk_slave {/ddr4_0/c0_ddr4_ui_clk (300 MHz)} Clk_xbar {/ddr4_0/c0_ddr4_ui_clk (300 MHz)} Master {/axi_ethernet_0_dma/M_AXI_SG} Slave {/ddr4_0/C0_DDR4_S_AXI} intc_ip {/axi_smc} master_apm {0}}  [get_bd_intf_pins axi_ethernet_0_dma/M_AXI_SG]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {/clk_wiz_0/clk_out1 (125 MHz)} Clk_slave {/ddr4_0/c0_ddr4_ui_clk (300 MHz)} Clk_xbar {/ddr4_0/c0_ddr4_ui_clk (300 MHz)} Master {/axi_ethernet_0_dma/M_AXI_MM2S} Slave {/ddr4_0/C0_DDR4_S_AXI} intc_ip {/axi_smc} master_apm {0}}  [get_bd_intf_pins axi_ethernet_0_dma/M_AXI_MM2S]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {/clk_wiz_0/clk_out1 (125 MHz)} Clk_slave {/ddr4_0/c0_ddr4_ui_clk (300 MHz)} Clk_xbar {/ddr4_0/c0_ddr4_ui_clk (300 MHz)} Master {/axi_ethernet_0_dma/M_AXI_S2MM} Slave {/ddr4_0/C0_DDR4_S_AXI} intc_ip {/axi_smc} master_apm {0}}  [get_bd_intf_pins axi_ethernet_0_dma/M_AXI_S2MM]

# Constant for the AXI Ethernet clk_en signal
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant const_clk_en
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0x01}] [get_bd_cells const_clk_en]
connect_bd_net [get_bd_pins const_clk_en/dout] [get_bd_pins axi_ethernet_0/clk_en]

# Add UART for the Echo server example application
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uart16550 axi_uart16550_0
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {/ddr4_0/addn_ui_clkout1 (100 MHz)} Clk_slave {Auto} Clk_xbar {/ddr4_0/addn_ui_clkout1 (100 MHz)} Master {/microblaze_0 (Periph)} Slave {/axi_uart16550_0/S_AXI} intc_ip {/microblaze_0_axi_periph} master_apm {0}}  [get_bd_intf_pins axi_uart16550_0/S_AXI]
apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {rs232_uart ( UART ) } Manual_Source {Auto}}  [get_bd_intf_pins axi_uart16550_0/UART]

connect_bd_net [get_bd_pins axi_uart16550_0/ip2intc_irpt] [get_bd_pins microblaze_0_xlconcat/In5]

# Add Timer for the Echo server example application
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_timer axi_timer_0
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {/ddr4_0/addn_ui_clkout1 (100 MHz)} Clk_slave {Auto} Clk_xbar {/ddr4_0/addn_ui_clkout1 (100 MHz)} Master {/microblaze_0 (Periph)} Slave {/axi_timer_0/S_AXI} intc_ip {/microblaze_0_axi_periph} master_apm {0}}  [get_bd_intf_pins axi_timer_0/S_AXI]

connect_bd_net [get_bd_pins axi_timer_0/interrupt] [get_bd_pins microblaze_0_xlconcat/In6]

# Restore current instance
current_bd_instance $oldCurInst

save_bd_design
