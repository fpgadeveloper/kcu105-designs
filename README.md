# KCU105 Designs

This repo contains a few Vivado designs for the KCU105 that we've used for testing various things.
We will not be maintaining or supporting this code, so use it as a guide only.

## Requirements

* Vivado 2018.2
* Xilinx SDK 2018.2

## Designs

### AXI Ethernet

This design uses the AXI Ethernet Subsystem IP to connect to the on-board Ethernet PHY
via an SGMII over LVDS link.

### PCS/PMA or SGMII and AXI Ethernet

This design uses the PCS/PMA or SGMII IP and the AXI Ethernet IP to connect to the on-board Ethernet PHY
via an SGMII over LVDS link. This is not the most efficient or simplest way of connecting to the Ethernet PHY but the
design allows us to experiment with the GMII link between the two cores.
