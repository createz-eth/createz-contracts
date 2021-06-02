import BN from 'bn.js';

export function equalsBn(func: (value: boolean, msg?: string) => void):
  (num1: BN | number, num2: BN | number) => void {

  return function (num1: BN | number, num2: BN | number): void {
    const bn1 = new BN(num1);
    const bn2 = new BN(num2);

    func(bn1.eq(bn2), `${bn1.toString()} is not equal to ${bn2.toString()}`);
  }
}

export function findFirstEvent<T>(logs: any[], type: string) {
  return (logs.find(e => e.event === `${type}`) as any) as T;
}
