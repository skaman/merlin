const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("spirv_tools", .{});

    const lib = b.addStaticLibrary(.{
        .name = "spirv_tools",
        .target = target,
        .optimize = optimize,
    });

    const tag = target.result.os.tag;
    if (tag == .windows) {
        lib.root_module.addCMacro("SPIRV_WINDOWS", "");
    } else if (tag == .linux) {
        lib.root_module.addCMacro("SPIRV_LINUX", "");
    } else if (tag == .macos) {
        lib.root_module.addCMacro("SPIRV_MAC", "");
    } else if (tag == .ios) {
        lib.root_module.addCMacro("SPIRV_IOS", "");
    } else if (tag == .tvos) {
        lib.root_module.addCMacro("SPIRV_TVOS", "");
    } else if (tag == .freebsd) {
        lib.root_module.addCMacro("SPIRV_FREEBSD", "");
    } else if (tag == .openbsd) {
        lib.root_module.addCMacro("SPIRV_OPENBSD", "");
    } else if (tag == .fuchsia) {
        lib.root_module.addCMacro("SPIRV_FUCHSIA", "");
    } else {
        std.log.err("Incompatible target platform.", .{});
        std.process.exit(1);
    }

    lib.linkLibCpp();
    lib.addIncludePath(b.path("upstream"));
    lib.addIncludePath(b.path("upstream/include"));
    lib.addIncludePath(b.path("generated"));

    const src_dir = "upstream/source/";
    lib.addCSourceFiles(.{
        .files = &.{
            // opt
            src_dir ++ "opt/fix_func_call_arguments.cpp",
            src_dir ++ "opt/aggressive_dead_code_elim_pass.cpp",
            src_dir ++ "opt/amd_ext_to_khr.cpp",
            src_dir ++ "opt/analyze_live_input_pass.cpp",
            src_dir ++ "opt/basic_block.cpp",
            src_dir ++ "opt/block_merge_pass.cpp",
            src_dir ++ "opt/block_merge_util.cpp",
            src_dir ++ "opt/build_module.cpp",
            src_dir ++ "opt/ccp_pass.cpp",
            src_dir ++ "opt/cfg_cleanup_pass.cpp",
            src_dir ++ "opt/cfg.cpp",
            src_dir ++ "opt/code_sink.cpp",
            src_dir ++ "opt/combine_access_chains.cpp",
            src_dir ++ "opt/compact_ids_pass.cpp",
            src_dir ++ "opt/composite.cpp",
            src_dir ++ "opt/const_folding_rules.cpp",
            src_dir ++ "opt/constants.cpp",
            src_dir ++ "opt/control_dependence.cpp",
            src_dir ++ "opt/convert_to_sampled_image_pass.cpp",
            src_dir ++ "opt/convert_to_half_pass.cpp",
            src_dir ++ "opt/copy_prop_arrays.cpp",
            src_dir ++ "opt/dataflow.cpp",
            src_dir ++ "opt/dead_branch_elim_pass.cpp",
            src_dir ++ "opt/dead_insert_elim_pass.cpp",
            src_dir ++ "opt/dead_variable_elimination.cpp",
            src_dir ++ "opt/decoration_manager.cpp",
            src_dir ++ "opt/debug_info_manager.cpp",
            src_dir ++ "opt/def_use_manager.cpp",
            src_dir ++ "opt/desc_sroa.cpp",
            src_dir ++ "opt/desc_sroa_util.cpp",
            src_dir ++ "opt/dominator_analysis.cpp",
            src_dir ++ "opt/dominator_tree.cpp",
            src_dir ++ "opt/eliminate_dead_constant_pass.cpp",
            src_dir ++ "opt/eliminate_dead_functions_pass.cpp",
            src_dir ++ "opt/eliminate_dead_functions_util.cpp",
            src_dir ++ "opt/eliminate_dead_io_components_pass.cpp",
            src_dir ++ "opt/eliminate_dead_members_pass.cpp",
            src_dir ++ "opt/eliminate_dead_output_stores_pass.cpp",
            src_dir ++ "opt/feature_manager.cpp",
            src_dir ++ "opt/fix_storage_class.cpp",
            src_dir ++ "opt/flatten_decoration_pass.cpp",
            src_dir ++ "opt/fold.cpp",
            src_dir ++ "opt/folding_rules.cpp",
            src_dir ++ "opt/fold_spec_constant_op_and_composite_pass.cpp",
            src_dir ++ "opt/freeze_spec_constant_value_pass.cpp",
            src_dir ++ "opt/function.cpp",
            src_dir ++ "opt/graphics_robust_access_pass.cpp",
            src_dir ++ "opt/if_conversion.cpp",
            src_dir ++ "opt/inline_exhaustive_pass.cpp",
            src_dir ++ "opt/inline_opaque_pass.cpp",
            src_dir ++ "opt/inline_pass.cpp",
            src_dir ++ "opt/instruction.cpp",
            src_dir ++ "opt/instruction_list.cpp",
            src_dir ++ "opt/interface_var_sroa.cpp",
            src_dir ++ "opt/invocation_interlock_placement_pass.cpp",
            src_dir ++ "opt/interp_fixup_pass.cpp",
            src_dir ++ "opt/opextinst_forward_ref_fixup_pass.cpp",
            src_dir ++ "opt/ir_context.cpp",
            src_dir ++ "opt/ir_loader.cpp",
            src_dir ++ "opt/licm_pass.cpp",
            src_dir ++ "opt/liveness.cpp",
            src_dir ++ "opt/local_access_chain_convert_pass.cpp",
            src_dir ++ "opt/local_redundancy_elimination.cpp",
            src_dir ++ "opt/local_single_block_elim_pass.cpp",
            src_dir ++ "opt/local_single_store_elim_pass.cpp",
            src_dir ++ "opt/loop_dependence.cpp",
            src_dir ++ "opt/loop_dependence_helpers.cpp",
            src_dir ++ "opt/loop_descriptor.cpp",
            src_dir ++ "opt/loop_fission.cpp",
            src_dir ++ "opt/loop_fusion.cpp",
            src_dir ++ "opt/loop_fusion_pass.cpp",
            src_dir ++ "opt/loop_peeling.cpp",
            src_dir ++ "opt/loop_utils.cpp",
            src_dir ++ "opt/loop_unroller.cpp",
            src_dir ++ "opt/loop_unswitch_pass.cpp",
            src_dir ++ "opt/mem_pass.cpp",
            src_dir ++ "opt/merge_return_pass.cpp",
            src_dir ++ "opt/modify_maximal_reconvergence.cpp",
            src_dir ++ "opt/module.cpp",
            src_dir ++ "opt/optimizer.cpp",
            src_dir ++ "opt/pass.cpp",
            src_dir ++ "opt/pass_manager.cpp",
            src_dir ++ "opt/private_to_local_pass.cpp",
            src_dir ++ "opt/propagator.cpp",
            src_dir ++ "opt/reduce_load_size.cpp",
            src_dir ++ "opt/redundancy_elimination.cpp",
            src_dir ++ "opt/register_pressure.cpp",
            src_dir ++ "opt/relax_float_ops_pass.cpp",
            src_dir ++ "opt/remove_dontinline_pass.cpp",
            src_dir ++ "opt/remove_duplicates_pass.cpp",
            src_dir ++ "opt/remove_unused_interface_variables_pass.cpp",
            src_dir ++ "opt/replace_desc_array_access_using_var_index.cpp",
            src_dir ++ "opt/replace_invalid_opc.cpp",
            src_dir ++ "opt/scalar_analysis.cpp",
            src_dir ++ "opt/scalar_analysis_simplification.cpp",
            src_dir ++ "opt/scalar_replacement_pass.cpp",
            src_dir ++ "opt/set_spec_constant_default_value_pass.cpp",
            src_dir ++ "opt/simplification_pass.cpp",
            src_dir ++ "opt/spread_volatile_semantics.cpp",
            src_dir ++ "opt/ssa_rewrite_pass.cpp",
            src_dir ++ "opt/strength_reduction_pass.cpp",
            src_dir ++ "opt/strip_debug_info_pass.cpp",
            src_dir ++ "opt/strip_nonsemantic_info_pass.cpp",
            src_dir ++ "opt/struct_cfg_analysis.cpp",
            src_dir ++ "opt/struct_packing_pass.cpp",
            src_dir ++ "opt/switch_descriptorset_pass.cpp",
            src_dir ++ "opt/trim_capabilities_pass.cpp",
            src_dir ++ "opt/type_manager.cpp",
            src_dir ++ "opt/types.cpp",
            src_dir ++ "opt/unify_const_pass.cpp",
            src_dir ++ "opt/upgrade_memory_model.cpp",
            src_dir ++ "opt/value_number_table.cpp",
            src_dir ++ "opt/vector_dce.cpp",
            src_dir ++ "opt/workaround1209.cpp",
            src_dir ++ "opt/wrap_opkill.cpp",
            // reduce
            src_dir ++ "reduce/change_operand_reduction_opportunity.cpp",
            src_dir ++ "reduce/change_operand_to_undef_reduction_opportunity.cpp",
            src_dir ++ "reduce/conditional_branch_to_simple_conditional_branch_opportunity_finder.cpp",
            src_dir ++ "reduce/conditional_branch_to_simple_conditional_branch_reduction_opportunity.cpp",
            src_dir ++ "reduce/merge_blocks_reduction_opportunity.cpp",
            src_dir ++ "reduce/merge_blocks_reduction_opportunity_finder.cpp",
            src_dir ++ "reduce/operand_to_const_reduction_opportunity_finder.cpp",
            src_dir ++ "reduce/operand_to_undef_reduction_opportunity_finder.cpp",
            src_dir ++ "reduce/operand_to_dominating_id_reduction_opportunity_finder.cpp",
            src_dir ++ "reduce/reducer.cpp",
            src_dir ++ "reduce/reduction_opportunity.cpp",
            src_dir ++ "reduce/reduction_opportunity_finder.cpp",
            src_dir ++ "reduce/reduction_pass.cpp",
            src_dir ++ "reduce/reduction_util.cpp",
            src_dir ++ "reduce/remove_block_reduction_opportunity.cpp",
            src_dir ++ "reduce/remove_block_reduction_opportunity_finder.cpp",
            src_dir ++ "reduce/remove_function_reduction_opportunity.cpp",
            src_dir ++ "reduce/remove_function_reduction_opportunity_finder.cpp",
            src_dir ++ "reduce/remove_instruction_reduction_opportunity.cpp",
            src_dir ++ "reduce/remove_selection_reduction_opportunity.cpp",
            src_dir ++ "reduce/remove_selection_reduction_opportunity_finder.cpp",
            src_dir ++ "reduce/remove_struct_member_reduction_opportunity.cpp",
            src_dir ++ "reduce/remove_unused_instruction_reduction_opportunity_finder.cpp",
            src_dir ++ "reduce/remove_unused_struct_member_reduction_opportunity_finder.cpp",
            src_dir ++ "reduce/simple_conditional_branch_to_branch_opportunity_finder.cpp",
            src_dir ++ "reduce/simple_conditional_branch_to_branch_reduction_opportunity.cpp",
            src_dir ++ "reduce/structured_construct_to_block_reduction_opportunity.cpp",
            src_dir ++ "reduce/structured_construct_to_block_reduction_opportunity_finder.cpp",
            src_dir ++ "reduce/structured_loop_to_selection_reduction_opportunity.cpp",
            src_dir ++ "reduce/structured_loop_to_selection_reduction_opportunity_finder.cpp",
            // link
            src_dir ++ "link/linker.cpp",
            // lint
            src_dir ++ "lint/linter.cpp",
            src_dir ++ "lint/divergence_analysis.cpp",
            src_dir ++ "lint/lint_divergent_derivatives.cpp",
            // diff
            src_dir ++ "diff/diff.cpp",
            // main
            src_dir ++ "util/bit_vector.cpp",
            src_dir ++ "util/parse_number.cpp",
            src_dir ++ "util/string_utils.cpp",
            src_dir ++ "assembly_grammar.cpp",
            src_dir ++ "binary.cpp",
            src_dir ++ "diagnostic.cpp",
            src_dir ++ "disassemble.cpp",
            src_dir ++ "enum_string_mapping.cpp",
            src_dir ++ "ext_inst.cpp",
            src_dir ++ "extensions.cpp",
            src_dir ++ "libspirv.cpp",
            src_dir ++ "name_mapper.cpp",
            src_dir ++ "opcode.cpp",
            src_dir ++ "operand.cpp",
            src_dir ++ "parsed_operand.cpp",
            src_dir ++ "print.cpp",
            src_dir ++ "software_version.cpp",
            src_dir ++ "spirv_endian.cpp",
            src_dir ++ "spirv_fuzzer_options.cpp",
            src_dir ++ "spirv_optimizer_options.cpp",
            src_dir ++ "spirv_reducer_options.cpp",
            src_dir ++ "spirv_target_env.cpp",
            src_dir ++ "spirv_validator_options.cpp",
            src_dir ++ "table.cpp",
            src_dir ++ "text.cpp",
            src_dir ++ "text_handler.cpp",
            src_dir ++ "to_string.cpp",
            src_dir ++ "val/validate.cpp",
            src_dir ++ "val/validate_adjacency.cpp",
            src_dir ++ "val/validate_annotation.cpp",
            src_dir ++ "val/validate_arithmetics.cpp",
            src_dir ++ "val/validate_atomics.cpp",
            src_dir ++ "val/validate_barriers.cpp",
            src_dir ++ "val/validate_bitwise.cpp",
            src_dir ++ "val/validate_builtins.cpp",
            src_dir ++ "val/validate_capability.cpp",
            src_dir ++ "val/validate_cfg.cpp",
            src_dir ++ "val/validate_composites.cpp",
            src_dir ++ "val/validate_constants.cpp",
            src_dir ++ "val/validate_conversion.cpp",
            src_dir ++ "val/validate_debug.cpp",
            src_dir ++ "val/validate_decorations.cpp",
            src_dir ++ "val/validate_derivatives.cpp",
            src_dir ++ "val/validate_extensions.cpp",
            src_dir ++ "val/validate_execution_limitations.cpp",
            src_dir ++ "val/validate_function.cpp",
            src_dir ++ "val/validate_id.cpp",
            src_dir ++ "val/validate_image.cpp",
            src_dir ++ "val/validate_interfaces.cpp",
            src_dir ++ "val/validate_instruction.cpp",
            src_dir ++ "val/validate_layout.cpp",
            src_dir ++ "val/validate_literals.cpp",
            src_dir ++ "val/validate_logicals.cpp",
            src_dir ++ "val/validate_memory.cpp",
            src_dir ++ "val/validate_memory_semantics.cpp",
            src_dir ++ "val/validate_mesh_shading.cpp",
            src_dir ++ "val/validate_misc.cpp",
            src_dir ++ "val/validate_mode_setting.cpp",
            src_dir ++ "val/validate_non_uniform.cpp",
            src_dir ++ "val/validate_primitives.cpp",
            src_dir ++ "val/validate_ray_query.cpp",
            src_dir ++ "val/validate_ray_tracing.cpp",
            src_dir ++ "val/validate_ray_tracing_reorder.cpp",
            src_dir ++ "val/validate_scopes.cpp",
            src_dir ++ "val/validate_small_type_uses.cpp",
            src_dir ++ "val/validate_tensor_layout.cpp",
            src_dir ++ "val/validate_type.cpp",
            src_dir ++ "val/basic_block.cpp",
            src_dir ++ "val/construct.cpp",
            src_dir ++ "val/function.cpp",
            src_dir ++ "val/instruction.cpp",
            src_dir ++ "val/validation_state.cpp",
        },
    });

    const spirv_headers = b.dependency("spirv_headers", .{
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibrary(spirv_headers.artifact("spirv_headers"));

    lib.addIncludePath(b.path("../spirv-headers/upstream/include"));
    lib.addIncludePath(b.path("../spirv-headers/upstream/include/spirv/unified1/"));

    b.installArtifact(lib);
}
