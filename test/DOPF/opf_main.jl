using IPowerLab
using Ipopt
using Gurobi
using JuMP
using Plots
ENV["GUROBI_HOME"] = "C:\\Program Files\\gurobi903\\win64" # change this based on your system

type=:AC_cases
lst = show_cases(true; type=type)
case_id = 3
date="2017-02-18"
grid = load_system(case_id; type=type, date=date)

# for visualization, although it's poor now, but his will be dealt with later
Plot_PowerGrid(grid; node_size=0.2,font_size=3)

time_horizon = [1]

SimulationSettings = DOPF_SimulationSettings(time_horizon = time_horizon,
    ac_grid_model = :Bθ,
    load_shedding = [:post], # if empty then no load shedding is allowed at all
    transmission_switching = [:post], # if empty then TS will be utilized pre and post contingencies
    substation_switching = Dict("splitting" => [:post], "reconf" => [:pre]),
    activate_temporal_switching = false, # to impose switching frequency constraints
    max_transmission_switching = Dict("pre_contingency" => Inf, "post_contingency" => Inf, "MCDT" => 1),
    max_substation_reconf = Dict("MCDT" => 1),
    max_busbar_splitting = Dict("pre_contingency" => Inf, "post_contingency" => Inf, "MCDT" => 1),

    contingency_types = [:ac_branch, :coupler], # all possibilities will be explained in documentation
    contingency_redispatch_condition = :loss_of_generation,

    NLP_solver = Ipopt.Optimizer,
    MILP_solver = Gurobi.Optimizer,
    Meta_solver = :none)


# Switching specifications
S = [] # IDs of buses considered as substations
H = [] # IDs of buses considered as hybrid substations with b2b Converters
B2B_cap = Dict() # dictionary (substation_id => capacity) of back to back converter capacity
ADB = [] # IDs of branches that are allowed to be switched on/off
FDB = [] # IDs of branches that are switchable but you prefer to give them a specific status based on some knowledge you have
FT = Dict() # Dictionary (branch_id => status) of fixed topology
switching_specs = Dict("substation_ids" => S, "hybrid_substation_ids" => H, "B2B_cap" => Dict(),
    "ac_active_dynamic_branch_ids" => ADB, "ac_fixed_dynamic_branch_ids" => FDB, "fixed_topology" => FT)

# Compile grid topology
compile_grid_topology!(grid, SimulationSettings, switching_specs)

all_gen_ids = [gen_id for gen_id in keys(grid.Generators) if grid.Generators[gen_id].GenType != :virtual]
contingency_specs = Dict("include_leafs" => true, "k" => 1)
generation_specs = Dict("commitable_gen_ids" => [], "non_commitable_gen_ids" => all_gen_ids, "fixed_commitments" => Dict(), "fixed_schedules" => Dict())
reference_node = 69
simulation_type = :OPF
prerequisites, virtual_market = compile_prerequisites_DOPF_no_market!(grid, simulation_type, SimulationSettings, contingency_specs, switching_specs,
    generation_specs; relaxed_physics_lines=[], relaxed_physics_nodes=[], relaxed_capacity_lines=[],reference_node=reference_node)

run_DOPF_simulation!(grid, SimulationSettings, prerequisites, virtual_market; update_grid=true)

update_grid_tables_DOPF!(grid; t=1, k=1)

println(grid.BusData_output)
println(grid.LineLoading)

profits_pre_switching = calculate_line_profits(grid, prerequisites; t=1, k=1, real_duals=true)

chains_pre_swiching, cycles, profit_in_cycle_pre_swiching, Δλ_in_cycle, PF_in_cycle = analyze_grid_chains(grid, profits_pre_switching)

print(profits_pre_switching)

profit_in_cycle_pre_swiching_sorted = sort(profit_in_cycle_pre_swiching)
most_profitable_chain_pre_switching = findfirst(x -> x == profit_in_cycle_pre_swiching_sorted[end], profit_in_cycle_pre_swiching)
profits_of_most_profitable_chain = filter(row -> row.line_id ∈ chains_pre_swiching[most_profitable_chain_pre_switching][1], profits_pre_switching)
println(profits_of_most_profitable_chain)