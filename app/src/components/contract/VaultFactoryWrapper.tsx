import {
  CreatorVaultFactory, VaultCreation
} from '../../../../types/web3-v1-contracts/CreatorVaultFactory';

/**
  * Provides abstraction on top of VaultFactory
  */
export interface VaultFactoryWrapper {

  /**
    * creates a new vault for given user address
    * @param address owner of the new vault
    * @param onTransactionHash callback on received transaction hash
    */
  create(address: string,
         onTransactionHash?: (hash: string) => void): Promise<string>
}

export class Web3VaultFactory implements VaultFactoryWrapper {

  private delegate: CreatorVaultFactory;

  constructor(delegate: CreatorVaultFactory) {
    this.delegate = delegate;
  }

  public async create(address: string, onTransactionHash: (hash: string) => void): Promise<string> {
    return this.delegate.methods.create(address)
    .send()
    .once('sending', () => console.log("sending"))
    .once('sent', () => console.log("sent"))
    .once('transactionHash', onTransactionHash)
    .then(res => {
      console.log(`received result ${JSON.stringify(res)}`);
      if (res.events && res.events.VaultCreation) {
        const creation = res.events.VaultCreation as VaultCreation;
        const vaultAddress = creation.returnValues._newContract;
        console.log(`New vault created at ${vaultAddress}`);
        return vaultAddress;
      }
      // TODO this is an error
      return "";
    });
  }
}