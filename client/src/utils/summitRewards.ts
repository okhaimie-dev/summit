import {
  START_TIMESTAMP,
  SUMMIT_DURATION_SECONDS,
  SUMMIT_XP_PER_SECOND,
} from '@/contexts/GameDirector';

export type SummitTimeStatus = {
  startTimestamp: number;
  currentTimestamp: number;
  secondsElapsed: number;
  totalDuration: number;
  secondsRemaining: number;
  percentRemaining: number; // 0..100
  xpPerSecond: number;
};

const clamp = (n: number, min: number, max: number) => Math.min(max, Math.max(min, n));

export function getSummitTimeStatus(currentTimestamp: number): SummitTimeStatus {
  const startTimestamp = START_TIMESTAMP;
  const totalDuration = SUMMIT_DURATION_SECONDS;
  const xpPerSecond = SUMMIT_XP_PER_SECOND;

  const safeTimestamp = Number.isFinite(currentTimestamp) ? currentTimestamp : 0;
  const secondsElapsed = Math.max(0, Math.floor(safeTimestamp - startTimestamp));
  const secondsRemaining = clamp(totalDuration - secondsElapsed, 0, totalDuration);
  const percentRemaining = totalDuration > 0 ? clamp((secondsRemaining / totalDuration) * 100, 0, 100) : 0;

  return {
    startTimestamp,
    currentTimestamp: safeTimestamp,
    secondsElapsed,
    totalDuration,
    secondsRemaining,
    percentRemaining,
    xpPerSecond,
  };
}

// Backward compat alias
export type SummitRewardsStatus = SummitTimeStatus;
export const getSummitRewardsStatus = getSummitTimeStatus;
