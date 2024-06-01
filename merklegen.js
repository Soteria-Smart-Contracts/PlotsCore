console.log('merklegen.js loaded');

//convert the whitelistAddresses to an array of addresses with the points number appended to the address end
let WhitelistAddresses = data2.map((address) => {
  return address.address;
});

let ClaimantAddresses = data1.map((address) => {
  return address.address + address.points;
});

WhitelistAddresses = WhitelistAddresses.concat(ClaimantAddresses);

console.log(WhitelistAddresses);

const leafNodesWhitelist = WhitelistAddresses.map(addr => keccak256(addr));
let WhitelistMerkleTree = new MerkleTree(leafNodesWhitelist, keccak256, { sortPairs: true });

// Get the Merkle Root of the Merkle Tree
const rootHashWhitelist = WhitelistMerkleTree.getRoot();
const rootHashWhitelistBytes32 = '0x' + WhitelistMerkleTree.getRoot().toString('hex');
console.log("Root Hash Whitelist: ", rootHashWhitelistBytes32);

// Function to generate hex proof for a claiming address
function GenerateHexProofWhitelist(claimingAddress) {
  claimingAddress = keccak256(claimingAddress);
  const hexProof = WhitelistMerkleTree.getHexProof(claimingAddress);
  const isAddressInTree = WhitelistMerkleTree.verify(hexProof, claimingAddress, rootHashWhitelist);

  return {
    hexProof: hexProof,
    isAddressInTree: isAddressInTree
  };
}
