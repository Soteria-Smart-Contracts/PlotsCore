console.log('merklegen.js loaded');

//convert the whitelistAddresses to an array of addresses with the points number appended to the address end
let ClaimantAddresses = data1.map((address) => {
  return address.address + address.points;
});


let WhitelistAddresses = data2.map((address) => {
  return address.address;
});

console.log(WhitelistAddresses);
console.log(ClaimantAddresses);


const leafNodesWhitelist = WhitelistAddresses.map(addr => keccak256(addr));
const leafNodesClaimants = ClaimantAddresses.map(addr => keccak256(addr));
let ClaimantsMerkleTree = new MerkleTree(leafNodesWhitelist, keccak256, { sortPairs: true});
let WhitelistMerkleTree = new MerkleTree(leafNodesClaimants, keccak256, { sortPairs: true});

// Get the Merkle Root of the Merkle Trees
const rootHashClaimants = ClaimantsMerkleTree.getRoot();
const rootHashWhitelist = WhitelistMerkleTree.getRoot();
const rootHashClaimantsBytes32 = '0x' + ClaimantsMerkleTree.getRoot().toString('hex');
const rootHashWhitelistBytes32 = '0x' + WhitelistMerkleTree.getRoot().toString('hex');
console.log("Root Hash Claimants: ", rootHashClaimantsBytes32);
console.log("Root Hash Whitelist: ", rootHashWhitelistBytes32);


// ***** ***** ***** ***** ***** ***** ***** ***** // 

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

function GenerateHexProofClaimants(claimingAddress) {

  claimingAddress = keccak256(claimingAddress);
  const hexProof = WhitelistMerkleTree.getHexProof(claimingAddress);
  const isAddressInTree = WhitelistMerkleTree.verify(hexProof, claimingAddress, rootHashClaimants);

  return {
    hexProof: hexProof,
    isAddressInTree: isAddressInTree
  };
}