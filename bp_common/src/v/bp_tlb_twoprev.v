
module bp_tlb
  import bp_common_pkg::*;
  import bp_common_aviary_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_inv_cfg
   `declare_bp_proc_params(bp_params_p)
   ,parameter tlb_els_p       = "inv"
   
   ,localparam lg_els_lp      = `BSG_SAFE_CLOG2(tlb_els_p)
   ,localparam entry_width_lp = `bp_pte_entry_leaf_width(paddr_width_p)
 )
 (input                               clk_i
  , input                             reset_i
  , input                             flush_i
  , input                             translation_en_i
  
  , input                             v_i
  , input                             w_i
  , input [vtag_width_p-1:0]          vtag_i
  , input [entry_width_lp-1:0]        entry_i
    
  , output logic                      v_o
  , output logic [entry_width_lp-1:0] entry_o
  
  , output logic                      miss_v_o
  , output logic [vtag_width_p-1:0]   miss_vtag_o
 );

`declare_bp_fe_be_if(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p);
bp_pte_entry_leaf_s r_entry, w_entry, passthrough_entry;
bp_pte_entry_leaf_s prev_r_entry, prev2_r_entry, r_entry_o;

logic [lg_els_lp-1:0] cam_w_addr, cam_r_addr, ram_addr;
logic                 r_v, w_v, cam_r_v;
logic 		                        bypass_en, bypass2_en;
logic [vtag_width_p-1:0]          prev_vtag, prev2_vtag;
logic                             new_read;
logic [entry_width_lp-1:0]        dummy_r_entry_o;
logic                             correct_bypass;
assign entry_o    = translation_en_i ? r_entry_o : passthrough_entry;
assign w_entry    = entry_i;
  
assign r_v        = v_i & ~w_i;
assign w_v        = v_i & w_i & translation_en_i;

assign ram_addr   = (w_i)? cam_w_addr : cam_r_addr;

assign passthrough_entry.ptag = miss_vtag_o;

bsg_dff_reset #(.width_p(1))
  r_v_reg
  (.clk_i(clk_i)
   ,.reset_i(reset_i)
   ,.data_i(r_v & (cam_r_v | ~translation_en_i))
   ,.data_o(new_read)
  );

always_ff @(posedge new_read) begin
  if(translation_en_i & (prev_vtag != vtag_i)) begin
    prev2_r_entry <= prev_r_entry;
    prev2_vtag    <= prev_vtag;
    prev_r_entry <=  r_entry;
    prev_vtag    <=   vtag_i;
  end
end

// always_ff @(posedge v_o) begin
  
//   correct_bypass <= ((bypass_en | bypass2_en) & (dummy_r_entry_o == r_entry_o));
// end

assign bypass_en = ((prev_vtag == vtag_i) & translation_en_i);
assign bypass2_en = ((prev2_vtag == vtag_i) & translation_en_i);

assign r_entry_o = bypass_en ? prev_r_entry :  bypass2_en ? prev2_r_entry : r_entry;        
assign v_o = (bypass_en | bypass2_en) ? 1'b1 : (new_read);

bsg_dff_reset #(.width_p(1))
  miss_v_reg
  (.clk_i(clk_i)
   ,.reset_i(reset_i)
   ,.data_i(r_v & ~(cam_r_v | ~translation_en_i))
   ,.data_o(miss_v_o)
  );

bsg_dff_reset #(.width_p(vtag_width_p))
  miss_vtag_reg
  (.clk_i(clk_i)
   ,.reset_i(reset_i)
   ,.data_i(vtag_i)
   ,.data_o(miss_vtag_o)
  );

bp_tlb_replacement #(.ways_p(dtlb_els_p))
  plru
  (.clk_i(clk_i)
   ,.reset_i(reset_i | flush_i)
   
   ,.v_i(cam_r_v)
   ,.way_i(cam_r_addr)
   
   ,.way_o(cam_w_addr)
  ); 
  
bsg_cam_1r1w 
  #(.els_p(dtlb_els_p)
    ,.width_p(vtag_width_p)
    ,.multiple_entries_p(0)
    ,.find_empty_entry_p(1)
  )
  vtag_cam
  (.clk_i(clk_i)
   ,.reset_i(reset_i | flush_i)
   ,.en_i(1'b1)//~bypass_en)
   
   ,.w_v_i(w_v)
   ,.w_set_not_clear_i(1'b1)
   ,.w_addr_i(cam_w_addr)
   ,.w_data_i(vtag_i)
  
   ,.r_v_i(r_v )//& (~bypass_en & ~bypass2_en)) //modified //this might alter write to entryRam process?
   ,.r_data_i(vtag_i)
   
   ,.r_v_o(cam_r_v)
   ,.r_addr_o(cam_r_addr)
   
   ,.empty_v_o()
   ,.empty_addr_o()
  );

bsg_mem_1rw_sync
  #(.width_p(entry_width_lp)
    ,.els_p(dtlb_els_p)
  )
  entry_ram
  (.clk_i(clk_i)
   ,.reset_i(reset_i)
   ,.data_i(w_entry)
   ,.addr_i(ram_addr)
   ,.v_i(cam_r_v | w_v) // (cam_r_v & (~bypass_en & ~bypass2_en))  |  w_v) //modif
   ,.w_i(w_v)
   ,.data_o(r_entry)
  );

endmodule
