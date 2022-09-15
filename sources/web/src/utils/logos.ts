import TempleLogo from '@/assets/temple-logo.png';
import TezosLogo from '@/assets/tezos-logo.svg';
import { ChainType, WalletType } from '@/wallets';

export const ChainLogos: Record<ChainType, string> = {
  [ChainType.Tezos]: TezosLogo,
};

export const WalletLogos: Record<WalletType, string> = {
  [WalletType.Temple]: TempleLogo,
};
