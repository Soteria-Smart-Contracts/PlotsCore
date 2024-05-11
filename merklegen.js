console.log('merklegen.js loaded');

//convert the whitelistAddresses to an array of addresses with the points number appended to the address end
let ClaimantAddresses = data1.map((address) => {
  return address.address + address.points;
});

console.log(ClaimantAddresses);

let WhitelistAddresses = data2.map((address) => {
  return address.address;
});


const leafNodesWhitelist = WhitelistAddresses.map(addr => keccak256(addr));
const leafNodesClaimants = ClaimantAddresses.map(addr => keccak256(addr));
let ClaimantsMerkleTree = new MerkleTree(leafNodesWhitelist, keccak256, { sortPairs: true});
let WhitelistMerkleTree = new MerkleTree(leafNodesClaimants, keccak256, { sortPairs: true});

// Get the Merkle Root of the Merkle Trees

const rootHashClaimantsBytes32 = '0x' + merkleTree.getRoot().toString('hex');
const rootHashWhitelistBytes32 = '0x' + WhitelistMerkleTree.getRoot().toString('hex');
console.log("Root Hash Claimants: ", rootHashClaimantsBytes32);
console.log("Root Hash Whitelist: ", rootHashWhitelistBytes32);


// ***** ***** ***** ***** ***** ***** ***** ***** // 

// Function to generate hex proof for a claiming address
function GenerateHexProofWhitelist(claimingAddress) {
  // `getHexProof` returns the neighbour leaf and all parent nodes hashes that will

  //convert the claimingAddress to an address with the points number appended to the address end and then hash it
  claimingAddress = keccak256(claimingAddress);
  // be required to derive the Merkle Trees root hash.
  const hexProof = WhitelistMerkleTree.getHexProof(claimingAddress);

  // ✅ - ❌: Verify if claiming address is in the merkle tree or not.
  // This would be implemented in your Solidity Smart Contract
  const isAddressInTree = WhitelistMerkleTree.verify(hexProof, claimingAddress, rootHash);

  return {
    hexProof: hexProof,
    isAddressInTree: isAddressInTree
  };
}

function GenerateHexProofClaimants(claimingAddress) {
  // `getHexProof` returns the neighbour leaf and all parent nodes hashes that will

  //convert the claimingAddress to an address with the points number appended to the address end and then hash it
  claimingAddress = keccak256(claimingAddress);
  // be required to derive the Merkle Trees root hash.
  const hexProof = WhitelistMerkleTree.getHexProof(claimingAddress);

  // ✅ - ❌: Verify if claiming address is in the merkle tree or not.
  // This would be implemented in your Solidity Smart Contract
  const isAddressInTree = WhitelistMerkleTree.verify(hexProof, claimingAddress, rootHashWhitelist);

  return {
    hexProof: hexProof,
    isAddressInTree: isAddressInTree
  };
}