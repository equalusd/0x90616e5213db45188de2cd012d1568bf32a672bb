const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();   // প্রথম signer কে owner বানাচ্ছি

  const Token = await hre.ethers.getContractFactory("EUSDToken");
  const token = await Token.deploy(deployer.address); // constructor argument পাঠানো হলো

  await token.waitForDeployment();

  console.log("✅ Deployed To:", await token.getAddress());
  console.log("👤 Owner:", deployer.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
