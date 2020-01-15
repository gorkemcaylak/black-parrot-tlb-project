/**
 *  bp_core.v
 *
 *  icache is connected to 0.
 *  dcache is connected to 1.
 */

module bp_core_minimal
 import bp_common_pkg::*;
 import bp_common_aviary_pkg::*;
 import bp_be_pkg::*;
 import bp_be_dcache_pkg::*;
 import bp_common_rv64_pkg::*;
 import bp_common_cfg_link_pkg::*;
  #(parameter bp_params_e bp_params_p = e_bp_single_core_cfg
    `declare_bp_proc_params(bp_params_p)
    `declare_bp_fe_be_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p)
    `declare_bp_lce_cce_if_widths(cce_id_width_p, lce_id_width_p, paddr_width_p, lce_assoc_p, dword_width_p, cce_block_width_p)

    , localparam way_id_width_lp = `BSG_SAFE_CLOG2(lce_assoc_p)

    , localparam cfg_bus_width_lp = `bp_cfg_bus_width(vaddr_width_p, core_id_width_p, cce_id_width_p, lce_id_width_p, cce_pc_width_p, cce_instr_width_p)
    , localparam dcache_lce_data_mem_pkt_width_lp=
      `bp_be_dcache_lce_data_mem_pkt_width(lce_sets_p, lce_assoc_p, cce_block_width_p)
    , localparam dcache_lce_tag_mem_pkt_width_lp=
      `bp_be_dcache_lce_tag_mem_pkt_width(lce_sets_p, lce_assoc_p, ptag_width_p)
    , localparam dcache_lce_stat_mem_pkt_width_lp=
      `bp_be_dcache_lce_stat_mem_pkt_width(lce_sets_p, lce_assoc_p)
    )
   (
    input          clk_i
    , input        reset_i

    // Config info
    , input [cfg_bus_width_lp-1:0] cfg_bus_i
    , output [vaddr_width_p-1:0] cfg_npc_data_o
    , output [dword_width_p-1:0] cfg_irf_data_o
    , output [dword_width_p-1:0] cfg_csr_data_o
    , output [1:0] cfg_priv_data_o

    // BP request side - Interface to LCE
    , input [1:0] lce_ready_i
    , input [1:0] lce_miss_i
    , input credits_full_i
    , input credits_empty_i

    , output logic [1:0] load_miss_o
    , output logic [1:0] store_miss_o
    , output logic [1:0] lr_miss_o
    , output logic [1:0] lr_hit_o
    , output logic [1:0] cache_v_o
    , output logic [1:0] uncached_load_req_o
    , output logic [1:0] uncached_store_req_o

    , output logic [1:0][cce_block_width_p-1:0] data_mem_data_o
    , output logic [1:0][paddr_width_p-1:0] miss_addr_o
    , output logic [1:0][way_id_width_lp-1:0] lru_way_o
    , output logic [1:0][lce_assoc_p-1:0] dirty_o
    , output logic [1:0] store_o
    , output logic [1:0][dword_width_p-1:0] store_data_o
    , output logic [1:0][1:0] size_op_o

    // response side - Interface from LCE
    , input [1:0][dcache_lce_data_mem_pkt_width_lp-1:0] data_mem_pkt_i
    , input [1:0] data_mem_pkt_v_i
    , output logic [1:0] data_mem_pkt_yumi_o

    , input [1:0][dcache_lce_tag_mem_pkt_width_lp-1:0] tag_mem_pkt_i
    , input [1:0] tag_mem_pkt_v_i
    , output logic [1:0] tag_mem_pkt_yumi_o

    , input [1:0][dcache_lce_stat_mem_pkt_width_lp-1:0] stat_mem_pkt_i
    , input [1:0] stat_mem_pkt_v_i
    , output logic [1:0] stat_mem_pkt_yumi_o

    , input                                        timer_irq_i
    , input                                        software_irq_i
    , input                                        external_irq_i

    );

  `declare_bp_be_dcache_lce_data_mem_pkt_s(lce_sets_p, lce_assoc_p, cce_block_width_p);
  `declare_bp_be_dcache_lce_tag_mem_pkt_s(lce_sets_p, lce_assoc_p, ptag_width_p);
  `declare_bp_be_dcache_lce_stat_mem_pkt_s(lce_sets_p, lce_assoc_p);

  bp_be_dcache_lce_data_mem_pkt_s data_mem_pkt;
  bp_be_dcache_lce_tag_mem_pkt_s tag_mem_pkt;
  bp_be_dcache_lce_stat_mem_pkt_s stat_mem_pkt;

  // TODO: fix interfaces for fe/be
  `declare_bp_fe_be_if(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p);

  bp_fe_queue_s fe_queue_li, fe_queue_lo;
  logic fe_queue_v_li, fe_queue_ready_lo;
  logic fe_queue_v_lo, fe_queue_yumi_li;

  bp_fe_cmd_s fe_cmd_li, fe_cmd_lo;
  logic fe_cmd_v_li, fe_cmd_ready_lo;
  logic fe_cmd_v_lo, fe_cmd_yumi_li;

  logic fe_cmd_processed_li;

  // stub unsued outputs at I$ index
  always_comb begin
    store_miss_o[0] = '0;
    lr_miss_o[0] = '0;
    lr_hit_o[0] = '0;
    cache_v_o[0] = '0;
    uncached_store_req_o[0] = '0;
    dirty_o[0] = '0;
    store_o[0] = '0;
    store_data_o[0] = '0;
    size_op_o[0] = '0;
  end

  bp_fe_top
   #(.bp_params_p(bp_params_p))
   fe
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.cfg_bus_i(cfg_bus_i)

     ,.fe_queue_o(fe_queue_li)
     ,.fe_queue_v_o(fe_queue_v_li)
     ,.fe_queue_ready_i(fe_queue_ready_lo)

     ,.fe_cmd_i(fe_cmd_lo)
     ,.fe_cmd_v_i(fe_cmd_v_lo)
     ,.fe_cmd_yumi_o(fe_cmd_yumi_li)

     ,.lce_ready_i(lce_ready_i[0])
     ,.lce_miss_i(lce_miss_i[0])

     ,.uncached_req_o(uncached_load_req_o[0])
     ,.miss_tv_o(load_miss_o[0])
     ,.miss_addr_tv_o(miss_addr_o[0])
     ,.lru_way_o(lru_way_o[0])

     ,.data_mem_data_o(data_mem_data_o[0])
     ,.data_mem_pkt_i(data_mem_pkt_i[0])
     ,.data_mem_pkt_v_i(data_mem_pkt_v_i[0])
     ,.data_mem_pkt_yumi_o(data_mem_pkt_yumi_o[0])

     ,.tag_mem_pkt_i(tag_mem_pkt_i[0])
     ,.tag_mem_pkt_v_i(tag_mem_pkt_v_i[0])
     ,.tag_mem_pkt_yumi_o(tag_mem_pkt_yumi_o[0])

     ,.stat_mem_pkt_v_i(stat_mem_pkt_v_i[0])
     ,.stat_mem_pkt_i(stat_mem_pkt_i[0])
     ,.stat_mem_pkt_yumi_o(stat_mem_pkt_yumi_o[0])
     );

  bsg_fifo_1r1w_small
   #(.width_p(fe_cmd_width_lp)
     ,.els_p(fe_cmd_fifo_els_p)
     ,.ready_THEN_valid_p(1)
     )
   fe_cmd_fifo
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.data_i(fe_cmd_li)
     ,.v_i(fe_cmd_v_li)
     ,.ready_o(fe_cmd_ready_lo)

     ,.data_o(fe_cmd_lo)
     ,.v_o(fe_cmd_v_lo)
     ,.yumi_i(fe_cmd_yumi_li)
     );
  wire fe_cmd_empty_lo = ~fe_cmd_v_lo;
  wire fe_cmd_full_lo  = ~fe_cmd_ready_lo;
  wire fe_cmd_fence_li = fe_cmd_v_lo;

  logic fe_queue_clr_li, fe_queue_deq_li, fe_queue_roll_li;
  bsg_fifo_1r1w_rolly
   #(.width_p(fe_queue_width_lp)
     ,.els_p(fe_queue_fifo_els_p)
     ,.ready_THEN_valid_p(1)
     )
   fe_queue_fifo
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.clr_v_i(fe_queue_clr_li)
     ,.deq_v_i(fe_queue_deq_li)
     ,.roll_v_i(fe_queue_roll_li)

     ,.data_i(fe_queue_li)
     ,.v_i(fe_queue_v_li)
     ,.ready_o(fe_queue_ready_lo)

     ,.data_o(fe_queue_lo)
     ,.v_o(fe_queue_v_lo)
     ,.yumi_i(fe_queue_yumi_li)
     );

  bp_be_top
   #(.bp_params_p(bp_params_p))
   be
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.cfg_bus_i(cfg_bus_i)
     ,.cfg_npc_data_o(cfg_npc_data_o)
     ,.cfg_irf_data_o(cfg_irf_data_o)
     ,.cfg_csr_data_o(cfg_csr_data_o)
     ,.cfg_priv_data_o(cfg_priv_data_o)

     ,.fe_queue_clr_o(fe_queue_clr_li)
     ,.fe_queue_deq_o(fe_queue_deq_li)
     ,.fe_queue_roll_o(fe_queue_roll_li)

     ,.fe_queue_i(fe_queue_lo)
     ,.fe_queue_v_i(fe_queue_v_lo)
     ,.fe_queue_yumi_o(fe_queue_yumi_li)

     ,.fe_cmd_o(fe_cmd_li)
     ,.fe_cmd_v_o(fe_cmd_v_li)
     ,.fe_cmd_ready_i(fe_cmd_ready_lo)
     ,.fe_cmd_fence_i(fe_cmd_fence_li)

     ,.lce_ready_i(lce_ready_i[1])
     ,.lce_miss_i(lce_miss_i[1])
     ,.load_miss_o(load_miss_o[1])
     ,.store_miss_o(store_miss_o[1])
     ,.store_hit_o(store_o[1])
     ,.lr_miss_o(lr_miss_o[1])
     ,.uncached_load_req_o(uncached_load_req_o[1])
     ,.uncached_store_req_o(uncached_store_req_o[1])
     ,.miss_addr_o(miss_addr_o[1])
     ,.store_data_o(store_data_o[1])
     ,.size_op_o(size_op_o[1])
     ,.lru_way_o(lru_way_o[1])
     ,.dirty_o(dirty_o[1])
     ,.lr_hit_tv_o(lr_hit_o[1])
     ,.cache_v_o(cache_v_o[1])

     ,.data_mem_data_o(data_mem_data_o[1])
     ,.data_mem_pkt_i(data_mem_pkt_i[1])
     ,.data_mem_pkt_v_i(data_mem_pkt_v_i[1])
     ,.data_mem_pkt_yumi_o(data_mem_pkt_yumi_o[1])

     ,.tag_mem_pkt_i(tag_mem_pkt_i[1])
     ,.tag_mem_pkt_v_i(tag_mem_pkt_v_i[1])
     ,.tag_mem_pkt_yumi_o(tag_mem_pkt_yumi_o[1])

     ,.stat_mem_pkt_v_i(stat_mem_pkt_v_i[1])
     ,.stat_mem_pkt_i(stat_mem_pkt_i[1])
     ,.stat_mem_pkt_yumi_o(stat_mem_pkt_yumi_o[1])

     ,.credits_full_i(credits_full_i)
     ,.credits_empty_i(credits_empty_i)

     ,.timer_irq_i(timer_irq_i)
     ,.software_irq_i(software_irq_i)
     ,.external_irq_i(external_irq_i)
     );

endmodule
