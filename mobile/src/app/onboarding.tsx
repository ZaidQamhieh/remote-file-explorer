import { useRouter } from 'expo-router';

import { OnboardingScreen } from '../features/onboarding/OnboardingScreen';
import { markOnboarded } from '../features/onboarding/onboardingState';
import { keyValue } from '../services';

export default function Onboarding() {
  const router = useRouter();
  return (
    <OnboardingScreen
      onComplete={() => {
        void markOnboarded(keyValue).then(() => router.replace('/'));
      }}
    />
  );
}
