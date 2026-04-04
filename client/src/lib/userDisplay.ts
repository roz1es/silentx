import type { ChatParticipant, User } from '@/types';

export function participantLabel(
  p: Pick<User, 'username'> & { displayName?: string }
): string {
  return p.displayName?.trim() || p.username;
}

export function chatParticipantLabel(p: ChatParticipant): string {
  return participantLabel(p);
}
