use beasts_nft::pack::PackableBeast;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, mock_call, start_cheat_block_timestamp_global,
    start_cheat_caller_address, stop_cheat_block_timestamp_global, stop_cheat_caller_address,
};
use starknet::{ContractAddress, get_block_timestamp};
use summit::logic::combat;
use summit::models::beast::{Beast, BeastUtilsTrait, LiveBeastStats};
use summit::systems::summit::{ISummitSystemDispatcher, ISummitSystemDispatcherTrait};
use crate::constants::{BEAST_WHALE, SUPER_BEAST_OWNER, SUPER_BEAST_TOKEN_ID, whale_beast_token_ids};

// Real mainnet contract addresses
fn BEAST_ADDRESS() -> ContractAddress {
    0x046dA8955829ADF2bDa310099A0063451923f02E648cF25A1203aac6335CF0e4.try_into().unwrap()
}

fn REAL_PLAYER() -> ContractAddress {
    0x0689701974d95364aAd9C2306Bc322A40a27fb775b0C97733FD0e36E900b1878.try_into().unwrap()
}

fn DUNGEON_ADDRESS() -> ContractAddress {
    0x00a67ef20b61a9846e1c82b411175e6ab167ea9f8632bd6c2091823c3629ec42.try_into().unwrap()
}

fn BEAST_DATA_ADDRESS() -> ContractAddress {
    0x74abc15c0ddef39bdf1ede2a643c07968d3ed5bacb0123db2d5b7154fbb35c7.try_into().unwrap()
}

fn ATTACK_POTION_ADDRESS() -> ContractAddress {
    0x111.try_into().unwrap()
}

fn REVIVE_POTION_ADDRESS() -> ContractAddress {
    0x222.try_into().unwrap()
}

fn EXTRA_LIFE_POTION_ADDRESS() -> ContractAddress {
    0x333.try_into().unwrap()
}

fn POISON_POTION_ADDRESS() -> ContractAddress {
    0x444.try_into().unwrap()
}

fn SKULL_TOKEN_ADDRESS() -> ContractAddress {
    0x555.try_into().unwrap()
}

fn CORPSE_TOKEN_ADDRESS() -> ContractAddress {
    0x666.try_into().unwrap()
}

// Helper: get tier for a beast token
fn get_tier_for_token(summit: ISummitSystemDispatcher, token_id: u32) -> u8 {
    let beast = summit.get_beast(token_id);
    combat::get_beast_tier(beast.fixed.id)
}

// Deploy summit contract without starting it
fn deploy_summit() -> ISummitSystemDispatcher {
    let contract = declare("summit_systems").unwrap().contract_class();
    let owner = REAL_PLAYER();
    let start_timestamp = 1000_u64;
    let summit_duration_seconds = 1000000_u64;

    let mut calldata = array![];
    calldata.append(owner.into());
    calldata.append(start_timestamp.into());
    calldata.append(summit_duration_seconds.into());
    calldata.append(DUNGEON_ADDRESS().into());
    calldata.append(BEAST_ADDRESS().into());
    calldata.append(BEAST_DATA_ADDRESS().into());
    calldata.append(ATTACK_POTION_ADDRESS().into());
    calldata.append(REVIVE_POTION_ADDRESS().into());
    calldata.append(EXTRA_LIFE_POTION_ADDRESS().into());
    calldata.append(POISON_POTION_ADDRESS().into());
    calldata.append(SKULL_TOKEN_ADDRESS().into());
    calldata.append(CORPSE_TOKEN_ADDRESS().into());

    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    let summit = ISummitSystemDispatcher { contract_address };

    summit
}

// Deploy summit contract and start it (ready for attack/claim testing)
fn deploy_summit_and_start() -> ISummitSystemDispatcher {
    let summit = deploy_summit();
    summit.start_summit();
    summit
}

fn mock_erc20_burn_from(token_address: ContractAddress, success: bool) {
    mock_call(token_address, selector!("burn_from"), success, 1000);
}

fn mock_erc20_transfer(token_address: ContractAddress, success: bool) {
    mock_call(token_address, selector!("transfer"), success, 1000);
}

// ===========================================
// CORE ATTACK / CLAIM TESTS
// ===========================================

#[test]
#[fork("mainnet")]
fn test_claim_summit_basic() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    // First attack on empty tier summit = claim (no combat)
    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    let tier = get_tier_for_token(summit, 60989);
    assert(summit.get_summit_beast_token_id(tier) == 60989, 'Wrong summit beast token id');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_claim_summit_with_extra_lives() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_extra_life_potion_address(), true);

    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 10, false);

    let tier = get_tier_for_token(summit, 60989);
    assert(summit.get_summit_beast_token_id(tier) == 60989, 'Should claim summit');

    let beast = summit.get_beast(60989);
    assert(beast.live.extra_lives == 10, 'Extra lives not applied');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Summit not playable',))]
fn test_attack_summit_not_started() {
    let summit = deploy_summit();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Not token owner',))]
fn test_attack_not_beast_owner() {
    let summit = deploy_summit_and_start();

    let fake_owner: ContractAddress = 0x123.try_into().unwrap();
    start_cheat_caller_address(summit.contract_address, fake_owner);

    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('attacking own beast',))]
fn test_attack_own_summit_beast() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    // First: claim the summit with beast 60989
    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    // Try to attack our own beast on the summit
    summit.attack(60989, attacking_beasts, 0, 0, false);
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_claim_with_attack_potions() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    // Claim with attack potions - claim path doesn't use them but shouldn't error
    let attacking_beasts = array![(60989, 1, 5)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    let tier = get_tier_for_token(summit, 60989);
    assert(summit.get_summit_beast_token_id(tier) == 60989, 'Should claim summit');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_claim_unsafe_basic() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    // Claim with defending_beast_token_id=0 (unsafe mode)
    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, true);

    let tier = get_tier_for_token(summit, 60989);
    assert(summit.get_summit_beast_token_id(tier) == 60989, 'Wrong summit beast token id');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Max 4000 extra lives',))]
fn test_attack_too_many_extra_life_potions() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 4001, false);

    stop_cheat_caller_address(summit.contract_address);
}

// ===========================================
// TWO-PLAYER COMBAT TEST
// ===========================================

#[test]
#[fork("mainnet")]
fn test_two_player_combat() {
    let summit = deploy_summit_and_start();

    // SUPER_BEAST_OWNER claims the summit with their beast
    start_cheat_caller_address(summit.contract_address, SUPER_BEAST_OWNER());
    let claim_beasts = array![(SUPER_BEAST_TOKEN_ID, 1_u16, 0_u8)].span();
    summit.attack(0, claim_beasts, 0, 0, false);
    let tier = get_tier_for_token(summit, SUPER_BEAST_TOKEN_ID);
    assert(summit.get_summit_beast_token_id(tier) == SUPER_BEAST_TOKEN_ID, 'Should claim summit');
    stop_cheat_caller_address(summit.contract_address);

    // REAL_PLAYER claims their own tier (or fights if same tier as SUPER_BEAST)
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    let attack_beasts = array![(60989, 1_u16, 0_u8)].span();
    summit.attack(0, attack_beasts, 0, 0, false);
    let real_tier = get_tier_for_token(summit, 60989);
    assert(summit.get_summit_beast_token_id(real_tier) == 60989, 'Should be on summit');
    stop_cheat_caller_address(summit.contract_address);
}

// ===========================================
// BEAST MANAGEMENT FUNCTIONS TESTS
// ===========================================

#[test]
#[fork("mainnet")]
fn test_feed_basic() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_corpse_token_address(), true);

    summit.feed(60989, 10);

    let beast = summit.get_beast(60989);
    assert(beast.live.bonus_health == 10, 'Bonus health not updated');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('No amount to feed',))]
fn test_feed_zero_amount() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    summit.feed(60989, 0);

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_add_extra_life_basic() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_extra_life_potion_address(), true);

    // First claim the summit
    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    summit.add_extra_life(60989, 3);

    let beast = summit.get_beast(60989);
    assert(beast.live.extra_lives == 3, 'Extra lives not added');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('No extra lives',))]
fn test_add_extra_life_zero_potions() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    // Claim first
    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    summit.add_extra_life(60989, 0);

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Not summit beast',))]
fn test_add_extra_life_not_summit_beast() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    // Don't claim - summit is empty for all tiers
    summit.add_extra_life(60989, 3);

    stop_cheat_caller_address(summit.contract_address);
}

// ===========================================
// STAT AND ENHANCEMENT FUNCTIONS TESTS
// ===========================================

#[test]
#[fork("mainnet")]
fn test_apply_stat_points_basic() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_skull_token_address(), true);

    let stats = summit::models::beast::Stats { specials: 0, wisdom: 0, diplomacy: 0, spirit: 5, luck: 3 };

    summit.apply_stat_points(60989, stats);

    let beast = summit.get_beast(60989);
    assert(beast.live.stats.spirit == 5, 'Spirit not updated');
    assert(beast.live.stats.luck == 3, 'Luck not updated');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_apply_stat_points_unlock_specials() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_skull_token_address(), true);

    let stats = summit::models::beast::Stats { specials: 1, wisdom: 0, diplomacy: 0, spirit: 0, luck: 0 };

    summit.apply_stat_points(60989, stats);

    let beast = summit.get_beast(60989);
    assert(beast.live.stats.specials == 1, 'Specials not unlocked');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('No upgrades chosen',))]
fn test_apply_stat_points_no_upgrades() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let stats = summit::models::beast::Stats { specials: 0, wisdom: 0, diplomacy: 0, spirit: 0, luck: 0 };

    summit.apply_stat_points(60989, stats);

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_apply_poison() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_poison_potion_address(), true);

    // Claim summit first
    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    summit.apply_poison(60989, 5);

    stop_cheat_caller_address(summit.contract_address);
}

// ===========================================
// SUMMIT AND LEADERBOARD FUNCTIONS TESTS
// ===========================================

#[test]
#[fork("mainnet")]
fn test_start_summit() {
    let summit = deploy_summit();

    summit.start_summit();

    // Summit started but all tiers are empty
    assert(summit.get_terminal_timestamp() > 0, 'Terminal timestamp not set');
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Summit already started',))]
fn test_start_summit_twice() {
    let summit = deploy_summit_and_start();

    summit.start_summit();
}

// ===========================================
// ADMIN FUNCTIONS TESTS
// ===========================================

#[test]
#[fork("mainnet")]
fn test_set_start_timestamp() {
    // Deploy with a future start timestamp so we can modify it
    let contract = declare("summit_systems").unwrap().contract_class();
    let owner = REAL_PLAYER();
    let start_timestamp = 9999999999_u64; // Future timestamp
    let summit_duration_seconds = 1000000_u64;

    let mut calldata = array![];
    calldata.append(owner.into());
    calldata.append(start_timestamp.into());
    calldata.append(summit_duration_seconds.into());
    calldata.append(DUNGEON_ADDRESS().into());
    calldata.append(BEAST_ADDRESS().into());
    calldata.append(BEAST_DATA_ADDRESS().into());
    calldata.append(ATTACK_POTION_ADDRESS().into());
    calldata.append(REVIVE_POTION_ADDRESS().into());
    calldata.append(EXTRA_LIFE_POTION_ADDRESS().into());
    calldata.append(POISON_POTION_ADDRESS().into());
    calldata.append(SKULL_TOKEN_ADDRESS().into());
    calldata.append(CORPSE_TOKEN_ADDRESS().into());

    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    let summit = ISummitSystemDispatcher { contract_address };

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let new_timestamp = 9999999998_u64; // Still future but different
    summit.set_start_timestamp(new_timestamp);

    assert(summit.get_start_timestamp() == new_timestamp, 'Timestamp not updated');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_withdraw_funds() {
    let summit = deploy_summit();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let token_address: ContractAddress = 0x999.try_into().unwrap();
    let amount: u256 = 1000;
    mock_erc20_transfer(token_address, true);

    summit.withdraw_funds(token_address, amount);

    stop_cheat_caller_address(summit.contract_address);
}

// ===========================================
// VIEW FUNCTIONS TESTS
// ===========================================

#[test]
#[fork("mainnet")]
fn test_get_start_timestamp() {
    let summit = deploy_summit();
    let start_time = summit.get_start_timestamp();
    assert(start_time == 1000_u64, 'Wrong start timestamp');
}

#[test]
#[fork("mainnet")]
fn test_get_terminal_timestamp() {
    let summit = deploy_summit_and_start();
    let terminal_block = summit.get_terminal_timestamp();
    assert(terminal_block > 0, 'Terminal block not set');
}

#[test]
#[fork("mainnet")]
fn test_get_summit_data() {
    let summit = deploy_summit_and_start();

    // Claim with REAL_PLAYER first
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);
    stop_cheat_caller_address(summit.contract_address);

    let tier = get_tier_for_token(summit, 60989);
    let (beast, taken_at, _summit_owner, poison_count, _poison_timestamp, _specials_hash) = summit
        .get_summit_data(tier);
    assert(beast.live.token_id == 60989, 'Wrong summit beast');
    assert(taken_at > 0, 'Taken at not set');
    assert(poison_count == 0, 'Poison count should be 0');
}

#[test]
#[fork("mainnet")]
fn test_get_summit_beast() {
    let summit = deploy_summit_and_start();

    // Claim first
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);
    stop_cheat_caller_address(summit.contract_address);

    let tier = get_tier_for_token(summit, 60989);
    let beast = summit.get_summit_beast(tier);
    assert(beast.live.token_id == 60989, 'Wrong summit beast');
}

#[test]
#[fork("mainnet")]
fn test_get_beast() {
    let summit = deploy_summit();
    let beast = summit.get_beast(60989);
    assert(beast.live.token_id == 60989, 'Wrong beast token id');
}

#[test]
#[fork("mainnet")]
fn test_get_all_addresses() {
    let summit = deploy_summit();
    assert(summit.get_dungeon_address() == DUNGEON_ADDRESS(), 'Wrong dungeon address');
    assert(summit.get_beast_address() == BEAST_ADDRESS(), 'Wrong beast address');
    assert(summit.get_beast_data_address() == BEAST_DATA_ADDRESS(), 'Wrong beast data address');
}

// ===========================================
// BEAST MODEL TESTS (crit_chance, spirit_reduction)
// ===========================================

fn create_test_beast(luck: u8, spirit: u8) -> Beast {
    let fixed = PackableBeast { id: 1, prefix: 1, suffix: 1, level: 10, health: 100, shiny: 0, animated: 0 };

    let live = LiveBeastStats {
        token_id: 1,
        current_health: 100,
        bonus_health: 0,
        bonus_xp: 0,
        attack_streak: 0,
        last_death_timestamp: 0,
        revival_count: 0,
        extra_lives: 0,
        summit_held_seconds: 0,
        stats: summit::models::beast::Stats { spirit, luck, specials: 0, wisdom: 0, diplomacy: 0 },
        rewards_earned: 0,
        rewards_claimed: 0,
        quest: summit::models::beast::Quest {
            captured_summit: 0, used_revival_potion: 0, used_attack_potion: 0, max_attack_streak: 0,
        },
    };

    Beast { fixed, live }
}

#[test]
fn test_crit_chance_zero_luck() {
    let beast = create_test_beast(0, 0);
    let crit = beast.crit_chance();
    assert(crit == 0, 'Crit should be 0%');
}

#[test]
fn test_crit_chance_luck_1() {
    let beast = create_test_beast(1, 0);
    let crit = beast.crit_chance();
    assert(crit == 10, 'Crit should be 10%');
}

#[test]
fn test_crit_chance_luck_5() {
    let beast = create_test_beast(5, 0);
    let crit = beast.crit_chance();
    assert(crit == 20, 'Crit should be 20%');
}

#[test]
fn test_crit_chance_luck_50() {
    let beast = create_test_beast(50, 0);
    let crit = beast.crit_chance();
    assert(crit == 65, 'Crit should be 65%');
}

#[test]
fn test_crit_chance_luck_70() {
    let beast = create_test_beast(70, 0);
    let crit = beast.crit_chance();
    assert(crit == 85, 'Crit should be 85%');
}

#[test]
fn test_crit_chance_luck_100() {
    let beast = create_test_beast(100, 0);
    let crit = beast.crit_chance();
    assert(crit == 100, 'Crit should be 100%');
}

#[test]
fn test_spirit_reduction_zero_spirit() {
    let beast = create_test_beast(0, 0);
    let reduction = beast.spirit_reduction();
    assert(reduction == 0, 'Reduction should be 0');
}

#[test]
fn test_spirit_reduction_spirit_1() {
    let beast = create_test_beast(0, 1);
    let reduction = beast.spirit_reduction();
    assert(reduction == 7200, 'Reduction should be 7200s');
}

#[test]
fn test_spirit_reduction_spirit_5() {
    let beast = create_test_beast(0, 5);
    let reduction = beast.spirit_reduction();
    assert(reduction == 14400, 'Reduction should be 14400s');
}

#[test]
fn test_spirit_reduction_spirit_50() {
    let beast = create_test_beast(0, 50);
    let reduction = beast.spirit_reduction();
    assert(reduction == 46800, 'Reduction should be 46800s');
}

#[test]
fn test_spirit_reduction_spirit_100() {
    let beast = create_test_beast(0, 100);
    let reduction = beast.spirit_reduction();
    assert(reduction == 72000, 'Reduction should be 72000s');
}

// ===========================================
// ADDITIONAL ATTACK EDGE CASE TESTS
// ===========================================

#[test]
#[fork("mainnet")]
fn test_claim_with_max_attack_potions() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let attacking_beasts = array![(60989, 1, 255)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    let tier = get_tier_for_token(summit, 60989);
    assert(summit.get_summit_beast_token_id(tier) == 60989, 'Should claim summit');
    stop_cheat_caller_address(summit.contract_address);
}

// ===========================================
// ADDITIONAL ADMIN SETTER TESTS
// ===========================================

#[test]
#[fork("mainnet")]
fn test_set_attack_potion_address() {
    let summit = deploy_summit();
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let new_address: ContractAddress = 0x999.try_into().unwrap();
    summit.set_attack_potion_address(new_address);

    assert(summit.get_attack_potion_address() == new_address, 'Address not updated');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_attack_potion_address_non_owner() {
    let summit = deploy_summit();
    let fake_owner: ContractAddress = 0x123.try_into().unwrap();
    start_cheat_caller_address(summit.contract_address, fake_owner);

    let new_address: ContractAddress = 0x999.try_into().unwrap();
    summit.set_attack_potion_address(new_address);

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_set_revive_potion_address() {
    let summit = deploy_summit();
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let new_address: ContractAddress = 0x999.try_into().unwrap();
    summit.set_revive_potion_address(new_address);

    assert(summit.get_revive_potion_address() == new_address, 'Address not updated');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_revive_potion_address_non_owner() {
    let summit = deploy_summit();
    let fake_owner: ContractAddress = 0x123.try_into().unwrap();
    start_cheat_caller_address(summit.contract_address, fake_owner);

    let new_address: ContractAddress = 0x999.try_into().unwrap();
    summit.set_revive_potion_address(new_address);

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_set_poison_potion_address() {
    let summit = deploy_summit();
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let new_address: ContractAddress = 0x999.try_into().unwrap();
    summit.set_poison_potion_address(new_address);

    assert(summit.get_poison_potion_address() == new_address, 'Address not updated');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_poison_potion_address_non_owner() {
    let summit = deploy_summit();
    let fake_owner: ContractAddress = 0x123.try_into().unwrap();
    start_cheat_caller_address(summit.contract_address, fake_owner);

    let new_address: ContractAddress = 0x999.try_into().unwrap();
    summit.set_poison_potion_address(new_address);

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_set_skull_token_address() {
    let summit = deploy_summit();
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let new_address: ContractAddress = 0x999.try_into().unwrap();
    summit.set_skull_token_address(new_address);

    assert(summit.get_skull_token_address() == new_address, 'Address not updated');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_skull_token_address_non_owner() {
    let summit = deploy_summit();
    let fake_owner: ContractAddress = 0x123.try_into().unwrap();
    start_cheat_caller_address(summit.contract_address, fake_owner);

    let new_address: ContractAddress = 0x999.try_into().unwrap();
    summit.set_skull_token_address(new_address);

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_set_corpse_token_address() {
    let summit = deploy_summit();
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let new_address: ContractAddress = 0x999.try_into().unwrap();
    summit.set_corpse_token_address(new_address);

    assert(summit.get_corpse_token_address() == new_address, 'Address not updated');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_corpse_token_address_non_owner() {
    let summit = deploy_summit();
    let fake_owner: ContractAddress = 0x123.try_into().unwrap();
    start_cheat_caller_address(summit.contract_address, fake_owner);

    let new_address: ContractAddress = 0x999.try_into().unwrap();
    summit.set_corpse_token_address(new_address);

    stop_cheat_caller_address(summit.contract_address);
}

// ===========================================
// ADDITIONAL STAT POINTS TESTS
// ===========================================

#[test]
#[fork("mainnet")]
fn test_apply_stat_points_unlock_wisdom() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_skull_token_address(), true);

    let stats = summit::models::beast::Stats { specials: 0, wisdom: 1, diplomacy: 0, spirit: 0, luck: 0 };

    summit.apply_stat_points(60989, stats);

    let beast = summit.get_beast(60989);
    assert(beast.live.stats.wisdom == 1, 'Wisdom not unlocked');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_apply_stat_points_unlock_diplomacy() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_skull_token_address(), true);

    let stats = summit::models::beast::Stats { specials: 0, wisdom: 0, diplomacy: 1, spirit: 0, luck: 0 };

    summit.apply_stat_points(60989, stats);

    let beast = summit.get_beast(60989);
    assert(beast.live.stats.diplomacy == 1, 'Diplomacy not unlocked');
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Specials already unlocked',))]
fn test_apply_stat_points_unlock_specials_twice() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_skull_token_address(), true);

    let stats = summit::models::beast::Stats { specials: 1, wisdom: 0, diplomacy: 0, spirit: 0, luck: 0 };

    summit.apply_stat_points(60989, stats);
    summit.apply_stat_points(60989, stats);

    stop_cheat_caller_address(summit.contract_address);
}

// ===========================================
// ADDITIONAL FEED TESTS
// ===========================================

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('beast has max bonus health',))]
fn test_feed_beyond_max_bonus_health() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_corpse_token_address(), true);

    summit.feed(60989, 2000);
    summit.feed(60989, 1);

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_feed_summit_beast() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_corpse_token_address(), true);

    // First claim the summit with beast 60989
    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    // Now feed the summit beast
    summit.feed(60989, 10);

    let beast = summit.get_beast(60989);
    assert(beast.live.bonus_health == 10, 'Bonus health not updated');

    stop_cheat_caller_address(summit.contract_address);
}

// ===========================================
// POISON EDGE CASE TESTS
// ===========================================

#[test]
#[fork("mainnet")]
fn test_apply_poison_multiple_times() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_poison_potion_address(), true);

    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    summit.apply_poison(60989, 5);
    summit.apply_poison(60989, 3);

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('No poison to apply',))]
fn test_apply_poison_zero_count() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    summit.apply_poison(60989, 0);

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('can only attack beast on summit',))]
fn test_apply_poison_not_summit_beast() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    // Beast 60989 is not on summit (no claim made)
    summit.apply_poison(60989, 5);

    stop_cheat_caller_address(summit.contract_address);
}

// ===========================================
// EXTRA LIFE EDGE CASES
// ===========================================

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Max 4000 extra lives',))]
fn test_add_extra_life_too_many() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    summit.add_extra_life(60989, 4001);

    stop_cheat_caller_address(summit.contract_address);
}

// ===========================================
// ADDITIONAL STAT POINTS EDGE CASES
// ===========================================

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('beast has max attributes',))]
fn test_apply_stat_points_exceed_max_spirit() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_skull_token_address(), true);

    let stats1 = summit::models::beast::Stats { specials: 0, wisdom: 0, diplomacy: 0, spirit: 100, luck: 0 };
    summit.apply_stat_points(60989, stats1);

    let stats2 = summit::models::beast::Stats { specials: 0, wisdom: 0, diplomacy: 0, spirit: 1, luck: 0 };
    summit.apply_stat_points(60989, stats2);

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('beast has max attributes',))]
fn test_apply_stat_points_exceed_max_luck() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_skull_token_address(), true);

    let stats1 = summit::models::beast::Stats { specials: 0, wisdom: 0, diplomacy: 0, spirit: 0, luck: 100 };
    summit.apply_stat_points(60989, stats1);

    let stats2 = summit::models::beast::Stats { specials: 0, wisdom: 0, diplomacy: 0, spirit: 0, luck: 1 };
    summit.apply_stat_points(60989, stats2);

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Wisdom already unlocked',))]
fn test_apply_stat_points_unlock_wisdom_twice() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_skull_token_address(), true);

    let stats = summit::models::beast::Stats { specials: 0, wisdom: 1, diplomacy: 0, spirit: 0, luck: 0 };

    summit.apply_stat_points(60989, stats);
    summit.apply_stat_points(60989, stats);

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Diplomacy already unlocked',))]
fn test_apply_stat_points_unlock_diplomacy_twice() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_skull_token_address(), true);

    let stats = summit::models::beast::Stats { specials: 0, wisdom: 0, diplomacy: 1, spirit: 0, luck: 0 };

    summit.apply_stat_points(60989, stats);
    summit.apply_stat_points(60989, stats);

    stop_cheat_caller_address(summit.contract_address);
}

// ==========================
// ADDITIONAL TESTS
// ==========================

#[test]
#[fork("mainnet")]
fn test_feed_mid_range_amount() {
    let summit = deploy_summit_and_start();
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_corpse_token_address(), true);

    summit.feed(60989, 1000);
    let beast = summit.get_beast(60989);
    assert(beast.live.bonus_health == 1000, 'Bonus health should be 1000');

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_apply_stat_points_spirit_only() {
    let summit = deploy_summit_and_start();
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_skull_token_address(), true);

    let stats = summit::models::beast::Stats { specials: 0, wisdom: 0, diplomacy: 0, spirit: 50, luck: 0 };
    summit.apply_stat_points(60989, stats);

    let beast = summit.get_beast(60989);
    assert(beast.live.stats.spirit == 50, 'Spirit should be 50');

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_apply_stat_points_luck_only() {
    let summit = deploy_summit_and_start();
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_skull_token_address(), true);

    let stats = summit::models::beast::Stats { specials: 0, wisdom: 0, diplomacy: 0, spirit: 0, luck: 75 };
    summit.apply_stat_points(60989, stats);

    let beast = summit.get_beast(60989);
    assert(beast.live.stats.luck == 75, 'Luck should be 75');

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_apply_stat_points_max_values() {
    let summit = deploy_summit_and_start();
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_skull_token_address(), true);

    let stats = summit::models::beast::Stats { specials: 0, wisdom: 0, diplomacy: 0, spirit: 100, luck: 100 };
    summit.apply_stat_points(60989, stats);

    let beast = summit.get_beast(60989);
    assert(beast.live.stats.spirit == 100, 'Spirit should be 100');
    assert(beast.live.stats.luck == 100, 'Luck should be 100');

    stop_cheat_caller_address(summit.contract_address);
}

// ==========================
// ADDITIONAL SUMMIT TESTS
// ==========================

#[test]
#[fork("mainnet")]
fn test_summit_beast_claim_then_verify() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    let tier = get_tier_for_token(summit, 60989);
    let summit_beast_id = summit.get_summit_beast_token_id(tier);
    assert(summit_beast_id == 60989, 'Beast should be on summit');

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_empty_summit_returns_zero_beast_id() {
    let summit = deploy_summit();
    // All tiers should return 0 before any claim
    assert(summit.get_summit_beast_token_id(1) == 0, 'T1 should be 0');
    assert(summit.get_summit_beast_token_id(2) == 0, 'T2 should be 0');
    assert(summit.get_summit_beast_token_id(3) == 0, 'T3 should be 0');
    assert(summit.get_summit_beast_token_id(4) == 0, 'T4 should be 0');
    assert(summit.get_summit_beast_token_id(5) == 0, 'T5 should be 0');
}

// ==========================
// POISON MECHANICS
// ==========================

#[test]
#[fork("mainnet")]
fn test_poison_damage_over_time() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_poison_potion_address(), true);

    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    summit.apply_poison(60989, 10);

    start_cheat_block_timestamp_global(get_block_timestamp() + 100);

    summit.apply_poison(60989, 1);

    stop_cheat_block_timestamp_global();
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_add_extra_life_applies_poison_first() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_poison_potion_address(), true);
    mock_erc20_burn_from(summit.get_extra_life_potion_address(), true);

    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    let beast_before_poison = summit.get_beast(60989);
    let health_before = beast_before_poison.live.current_health;

    summit.apply_poison(60989, 5);

    start_cheat_block_timestamp_global(get_block_timestamp() + 10);

    summit.add_extra_life(60989, 3);

    let beast = summit.get_beast(60989);
    assert(beast.live.extra_lives == 3, 'Extra lives not added');
    assert(beast.live.current_health < health_before, 'Poison damage not applied');

    stop_cheat_block_timestamp_global();
    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_add_extra_life_overflow_prevention() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_extra_life_potion_address(), true);

    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    summit.add_extra_life(60989, 3990);

    let beast = summit.get_beast(60989);
    assert(beast.live.extra_lives == 3990, 'Extra lives not set');

    summit.add_extra_life(60989, 20);

    let beast_after = summit.get_beast(60989);
    assert(beast_after.live.extra_lives == 4000, 'Should cap at 4000');

    stop_cheat_caller_address(summit.contract_address);
}

// ==========================
// ADMIN TESTS
// ==========================

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Summit already started',))]
fn test_set_start_timestamp_after_summit_started() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    summit.set_start_timestamp(9999999999_u64);

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_set_extra_life_potion_address() {
    let summit = deploy_summit();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());

    let new_address: ContractAddress = 0xFED.try_into().unwrap();
    summit.set_extra_life_potion_address(new_address);

    assert(summit.get_extra_life_potion_address() == new_address, 'Extra life addr not set');

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_extra_life_potion_address_non_owner() {
    let summit = deploy_summit();

    let new_address: ContractAddress = 0xFED.try_into().unwrap();
    summit.set_extra_life_potion_address(new_address);
}

// ==========================
// P0 TESTS: FUNDS CUSTODY
// ==========================

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_withdraw_funds_non_owner() {
    let summit = deploy_summit();

    let fake_owner: ContractAddress = 0x123.try_into().unwrap();
    start_cheat_caller_address(summit.contract_address, fake_owner);

    let token_address: ContractAddress = 0x999.try_into().unwrap();
    let amount: u256 = 1000;
    summit.withdraw_funds(token_address, amount);

    stop_cheat_caller_address(summit.contract_address);
}

// ==========================
// P0 TESTS: ACCESS CONTROL
// ==========================

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_start_timestamp_non_owner() {
    let contract = declare("summit_systems").unwrap().contract_class();
    let owner = REAL_PLAYER();
    let start_timestamp = 9999999999_u64;
    let summit_duration_seconds = 1000000_u64;

    let mut calldata = array![];
    calldata.append(owner.into());
    calldata.append(start_timestamp.into());
    calldata.append(summit_duration_seconds.into());
    calldata.append(DUNGEON_ADDRESS().into());
    calldata.append(BEAST_ADDRESS().into());
    calldata.append(BEAST_DATA_ADDRESS().into());
    calldata.append(ATTACK_POTION_ADDRESS().into());
    calldata.append(REVIVE_POTION_ADDRESS().into());
    calldata.append(EXTRA_LIFE_POTION_ADDRESS().into());
    calldata.append(POISON_POTION_ADDRESS().into());
    calldata.append(SKULL_TOKEN_ADDRESS().into());
    calldata.append(CORPSE_TOKEN_ADDRESS().into());

    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    let summit = ISummitSystemDispatcher { contract_address };

    let fake_owner: ContractAddress = 0x123.try_into().unwrap();
    start_cheat_caller_address(summit.contract_address, fake_owner);
    summit.set_start_timestamp(1000_u64);
    stop_cheat_caller_address(summit.contract_address);
}

// ==========================
// EXTRA LIVES EDGE CASE TESTS
// ==========================

#[test]
#[fork("mainnet")]
fn test_add_extra_lives_small_amount() {
    let summit = deploy_summit_and_start();
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_extra_life_potion_address(), true);

    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    summit.add_extra_life(60989, 10);
    let beast = summit.get_beast(60989);
    assert(beast.live.extra_lives == 10, 'Extra lives should be 10');

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_add_extra_lives_medium_amount() {
    let summit = deploy_summit_and_start();
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_extra_life_potion_address(), true);

    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    summit.add_extra_life(60989, 500);
    let beast = summit.get_beast(60989);
    assert(beast.live.extra_lives == 500, 'Extra lives should be 500');

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_add_extra_lives_near_max() {
    let summit = deploy_summit_and_start();
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_extra_life_potion_address(), true);

    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    summit.add_extra_life(60989, 3999);
    let beast = summit.get_beast(60989);
    assert(beast.live.extra_lives == 3999, 'Extra lives should be 3999');

    stop_cheat_caller_address(summit.contract_address);
}

// ==========================
// UNIT TESTS FOR BEAST MODEL
// ==========================

#[test]
fn test_crit_chance_luck_2() {
    let beast = create_test_beast(2, 0);
    let crit = beast.crit_chance();
    assert(crit == 14, 'Crit should be 14%');
}

#[test]
fn test_crit_chance_luck_3() {
    let beast = create_test_beast(3, 0);
    let crit = beast.crit_chance();
    assert(crit == 17, 'Crit should be 17%');
}

#[test]
fn test_crit_chance_luck_4() {
    let beast = create_test_beast(4, 0);
    let crit = beast.crit_chance();
    assert(crit == 19, 'Crit should be 19%');
}

#[test]
fn test_crit_chance_luck_6() {
    let beast = create_test_beast(6, 0);
    let crit = beast.crit_chance();
    assert(crit == 21, 'Crit should be 21%');
}

#[test]
fn test_crit_chance_luck_71() {
    let beast = create_test_beast(71, 0);
    let crit = beast.crit_chance();
    assert(crit == 85, 'Crit should be 85%');
}

#[test]
fn test_spirit_reduction_spirit_2() {
    let beast = create_test_beast(0, 2);
    let reduction = beast.spirit_reduction();
    assert(reduction == 10080, 'Reduction should be 10080s');
}

#[test]
fn test_spirit_reduction_spirit_3() {
    let beast = create_test_beast(0, 3);
    let reduction = beast.spirit_reduction();
    assert(reduction == 12240, 'Reduction should be 12240s');
}

#[test]
fn test_spirit_reduction_spirit_4() {
    let beast = create_test_beast(0, 4);
    let reduction = beast.spirit_reduction();
    assert(reduction == 13680, 'Reduction should be 13680s');
}

#[test]
fn test_spirit_reduction_spirit_6() {
    let beast = create_test_beast(0, 6);
    let reduction = beast.spirit_reduction();
    assert(reduction == 15120, 'Reduction should be 15120s');
}

#[test]
fn test_spirit_reduction_spirit_70() {
    let beast = create_test_beast(0, 70);
    let reduction = beast.spirit_reduction();
    assert(reduction == 61200, 'Reduction should be 61200s');
}

#[test]
fn test_spirit_reduction_spirit_71() {
    let beast = create_test_beast(0, 71);
    let reduction = beast.spirit_reduction();
    assert(reduction == 61560, 'Reduction should be 61560s');
}

// ==========================
// FUZZ TESTS FOR BEAST MODEL
// ==========================

#[test]
#[fuzzer(runs: 101)]
fn fuzz_test_crit_chance_bounds(luck: u8) {
    let beast = create_test_beast(luck, 0);
    let crit = beast.crit_chance();

    if luck == 0 {
        assert(crit == 0, 'Luck 0 should give 0% crit');
    } else if luck == 1 {
        assert(crit == 10, 'Luck 1 should give 10% crit');
    } else if luck <= 5 {
        assert(crit >= 10 && crit <= 20, 'Low luck range invalid');
    } else if luck <= 70 {
        assert(crit >= 20 && crit <= 85, 'Mid luck range invalid');
    } else {
        assert(crit >= 85, 'High luck should be >= 85%');
    }
}

#[test]
#[fuzzer(runs: 101)]
fn fuzz_test_spirit_reduction_bounds(spirit: u8) {
    let beast = create_test_beast(0, spirit);
    let reduction = beast.spirit_reduction();

    if spirit == 0 {
        assert(reduction == 0, 'Spirit 0 should give 0s');
    } else if spirit == 1 {
        assert(reduction == 7200, 'Spirit 1 should give 7200s');
    } else if spirit <= 5 {
        assert(reduction >= 7200 && reduction <= 14400, 'Low spirit range invalid');
    } else if spirit <= 70 {
        assert(reduction >= 14400 && reduction <= 61200, 'Mid spirit range invalid');
    } else {
        assert(reduction >= 61200, 'High spirit range invalid');
    }
}

#[test]
#[fuzzer(runs: 101)]
fn fuzz_test_crit_chance_monotonic(luck: u8) {
    if luck > 0 {
        let beast_current = create_test_beast(luck, 0);
        let beast_previous = create_test_beast(luck - 1, 0);

        let crit_current = beast_current.crit_chance();
        let crit_previous = beast_previous.crit_chance();

        assert(crit_current >= crit_previous, 'Crit should increase with luck');
    }
}

#[test]
#[fuzzer(runs: 101)]
fn fuzz_test_spirit_reduction_monotonic(spirit: u8) {
    if spirit > 1 {
        let beast_current = create_test_beast(0, spirit);
        let beast_previous = create_test_beast(0, spirit - 1);

        let reduction_current = beast_current.spirit_reduction();
        let reduction_previous = beast_previous.spirit_reduction();

        assert(reduction_current >= reduction_previous, 'Reduction should increase');
    }
}

// ==========================
// SUMMIT DURATION TEST
// ==========================

#[test]
#[fork("mainnet")]
fn test_get_summit_duration_blocks() {
    let summit = deploy_summit();
    let duration = summit.get_summit_duration_seconds();
    assert(duration == 1000000_u64, 'Wrong summit duration');
}

#[test]
#[fork("mainnet")]
fn test_feed_max_bonus_health() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_corpse_token_address(), true);

    summit.feed(60989, 2000);

    let beast = summit.get_beast(60989);
    assert(beast.live.bonus_health == 2000, 'Max bonus health not set');

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_feed_increases_current_health_for_summit_beast() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_corpse_token_address(), true);

    // First claim the summit
    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);

    let beast_before = summit.get_beast(60989);
    let health_before = beast_before.live.current_health;

    // Feed the summit beast
    summit.feed(60989, 50);

    let beast_after = summit.get_beast(60989);
    assert(beast_after.live.bonus_health == 50, 'Bonus health not set');
    assert(beast_after.live.current_health == health_before + 50, 'Current health not increased');

    stop_cheat_caller_address(summit.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_feed_non_summit_beast_only_bonus_health() {
    let summit = deploy_summit_and_start();

    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    mock_erc20_burn_from(summit.get_corpse_token_address(), true);

    // Feed a beast that's not on any summit
    summit.feed(60989, 50);

    let beast = summit.get_beast(60989);
    assert(beast.live.bonus_health == 50, 'Bonus health not set');
    assert(beast.live.current_health == 0, 'Current health should be 0');

    stop_cheat_caller_address(summit.contract_address);
}

// ==========================
// TIER-SPECIFIC TESTS
// ==========================

#[test]
#[fork("mainnet")]
fn test_independent_tier_summits() {
    let summit = deploy_summit_and_start();

    // REAL_PLAYER claims their tier
    start_cheat_caller_address(summit.contract_address, REAL_PLAYER());
    let attacking_beasts = array![(60989, 1, 0)].span();
    summit.attack(0, attacking_beasts, 0, 0, false);
    let tier_a = get_tier_for_token(summit, 60989);
    stop_cheat_caller_address(summit.contract_address);

    // SUPER_BEAST_OWNER claims their tier
    start_cheat_caller_address(summit.contract_address, SUPER_BEAST_OWNER());
    let claim_beasts = array![(SUPER_BEAST_TOKEN_ID, 1_u16, 0_u8)].span();
    summit.attack(0, claim_beasts, 0, 0, false);
    let tier_b = get_tier_for_token(summit, SUPER_BEAST_TOKEN_ID);
    stop_cheat_caller_address(summit.contract_address);

    // Verify both are on their respective tier summits
    assert(summit.get_summit_beast_token_id(tier_a) == 60989, 'Wrong beast on tier a');
    assert(summit.get_summit_beast_token_id(tier_b) == SUPER_BEAST_TOKEN_ID, 'Wrong beast on tier b');
}
