import { defineConfig } from "apibara/config";

export default defineConfig({
  runtimeConfig: {
    summit: {
      // Summit game contract address (mainnet)
      summitContractAddress:
        "0x06243275cb33ec8a1e6782da1683430708ad43c14bc57136d4350448a46eb72c",
      // Beasts NFT contract address (mainnet)
      beastsContractAddress:
        "0x046da8955829adf2bda310099a0063451923f02e648cf25a1203aac6335cf0e4",
      // Dojo World contract address (Loot Survivor mainnet)
      dojoWorldAddress:
        "0x02ef591697f0fd9adc0ba9dbe0ca04dabad80cf95f08ba02e435d9cb6698a28a",
      // EntityStats dungeon filter (Beast dungeon)
      entityStatsDungeon:
        "0x0000000000000000000000000000000000000000000000000000000000000006",
      // CollectableEntity dungeon filter (Loot Survivor dungeon)
      collectableEntityDungeon:
        "0x00a67ef20b61a9846e1c82b411175e6ab167ea9f8632bd6c2091823c3629ec42",
      // Corpse contract address (mainnet)
      corpseContractAddress:
        "0x0195685bd2bce86e4ebe4ea5ef44d9dc00c4e7c6e362d428abdb618b4739c25c",
      // Skull contract address (mainnet)
      skullContractAddress:
        "0x0168acb060a52a3acdf8b844afaf8172c0709a1469bee07f251d7ea21b1a436a",
      // Mainnet DNA stream URL
      streamUrl: process.env.STREAM_URL,
      // Starting block - use earliest block needed for Dojo events
      startingBlock: "2209828",
      // PostgreSQL connection string
      databaseUrl: process.env.DATABASE_URL,
      // RPC URL for fetching beast metadata
      rpcUrl: "https://api.cartridge.gg/x/starknet/mainnet/rpc/v0_10",
    },
  },
});
