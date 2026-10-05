/** One toggle chip of the day editor: a flow level, a symptom, a test result. */
export function Chip({
  label,
  selected,
  onPress,
  disabled,
}: {
  label: string;
  selected: boolean;
  onPress: () => void;
  disabled: boolean;
}) {
  return (
    <button
      type="button"
      className={selected ? 'chip chip-selected' : 'chip'}
      aria-pressed={selected}
      onClick={onPress}
      disabled={disabled}
    >
      {label}
    </button>
  );
}
