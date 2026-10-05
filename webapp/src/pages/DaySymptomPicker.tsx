import { useId, useState } from 'react';

import { useT } from '../i18n/t';
import { tagMatchesQuery, type SurfacedCategory } from '../lib/day/categories';
import { Chip } from './DayChip';

/**
 * The day editor's symptom picker: the app's `CategoryPicker`
 * (lib/ui/components/category_picker.dart) on the web. A search field that
 * filters the chips, a "Recent" row of the profile's latest tags, and one
 * section per category that opens and closes.
 *
 * It replaces a single open list of every category. On a phone that list
 * ran to some four thousand pixels, with the measurements, the tests and
 * the note underneath all of it.
 *
 * One deliberate difference from the app: a category starts closed unless
 * it holds something logged for this day. The app's picker is a sheet of
 * its own with the search pinned above it; here it shares a page with five
 * other sections, and twenty open categories bury them.
 *
 * Someone who can only read the day gets what was logged and nothing else:
 * no search, no recent row, no empty categories of disabled chips.
 *
 * Selection belongs to the caller. This component keeps only what is on
 * screen: the search text and which sections are open.
 */

export interface PickerTag {
  code: string;
  display: string;
}

export interface PickerCategory {
  category: SurfacedCategory;
  tags: PickerTag[];
}

function withMember(set: ReadonlySet<string>, member: string, present: boolean) {
  if (set.has(member) === present) return set;
  const next = new Set(set);
  if (present) next.add(member);
  else next.delete(member);
  return next;
}

export function DaySymptomPicker(props: {
  /** The categories to offer, in order, each with its tags. */
  categories: PickerCategory[];
  /** The profile's own tags, drawn as a last section. */
  customTags: PickerTag[];
  /** The codes on this day's entry. */
  selected: readonly string[];
  /** The profile's latest tag codes, newest first. */
  recentCodes: readonly string[];
  /** True for someone who can read the day but not write it. */
  readOnly: boolean;
  /** A chip was pressed; `categoryName` is null for one of the profile's own tags. */
  onToggle: (code: string, categoryName: string | null) => void;
}) {
  const t = useT();
  const baseId = useId();
  const [query, setQuery] = useState('');
  // A section the reader opened or closed by hand stays as they left it.
  // One they have not touched follows the day: open while it holds
  // something logged.
  const [opened, setOpened] = useState<ReadonlySet<string>>(new Set());
  const [closed, setClosed] = useState<ReadonlySet<string>>(new Set());

  const selected = new Set(props.selected);
  const searching = query.trim() !== '';

  if (props.readOnly) {
    const logged = props.categories
      .map(({ category, tags }) => ({
        category,
        tags: tags.filter((tag) => selected.has(tag.code)),
      }))
      .filter((entry) => entry.tags.length > 0);
    const loggedCustom = props.customTags.filter((tag) => selected.has(tag.code));
    if (logged.length === 0 && loggedCustom.length === 0) {
      return <p className="card-body">{t('webDayNoSymptomsLogged')}</p>;
    }
    return (
      <>
        {logged.map(({ category, tags }) => (
          <div key={category.name} className="tag-category">
            <h2 className="tag-category-label">{category.label}</h2>
            <div className="chip-row" role="group" aria-label={category.label}>
              {tags.map((tag) => (
                <Chip key={tag.code} label={tag.display} selected onPress={() => {}} disabled />
              ))}
            </div>
          </div>
        ))}
        {loggedCustom.length > 0 ? (
          <div className="tag-category">
            <h2 className="tag-category-label">{t('daySheetCustomTagsLabel')}</h2>
            <div className="chip-row" role="group" aria-label={t('daySheetCustomTagsLabel')}>
              {loggedCustom.map((tag) => (
                <Chip key={tag.code} label={tag.display} selected onPress={() => {}} disabled />
              ))}
            </div>
          </div>
        ) : null}
      </>
    );
  }

  const setSection = (name: string, open: boolean) => {
    setOpened((current) => withMember(current, name, open));
    setClosed((current) => withMember(current, name, !open));
  };

  // Pressing a chip pins its section open: without this, clearing the only
  // chip in a section that was open because of it would shut the section
  // under the reader's finger.
  const press = (code: string, categoryName: string) => {
    setSection(categoryName, true);
    props.onToggle(code, categoryName);
  };

  const categoryOf = new Map<string, { name: string; tag: PickerTag }>();
  for (const { category, tags } of props.categories) {
    for (const tag of tags) categoryOf.set(tag.code, { name: category.name, tag });
  }
  // A recent tag already on the day is left out: it shows, selected, in its
  // own section, and a second chip for the same toggle only confuses.
  const recent = props.recentCodes
    .filter((code) => !selected.has(code))
    .map((code) => categoryOf.get(code))
    .filter((entry) => entry !== undefined);

  const sections = props.categories
    .map(({ category, tags }) => ({
      category,
      tags: searching ? tags.filter((tag) => tagMatchesQuery(tag.display, query)) : tags,
      hasSelection: tags.some((tag) => selected.has(tag.code)),
    }))
    // While searching, a category with nothing matching drops out.
    .filter((entry) => !searching || entry.tags.length > 0);
  const customTags = searching
    ? props.customTags.filter((tag) => tagMatchesQuery(tag.display, query))
    : props.customTags;

  const searchId = `${baseId}-search`;
  const recentId = `${baseId}-recent`;

  return (
    <>
      <div className="tag-search">
        <label className="visually-hidden" htmlFor={searchId}>
          {t('daySheetTagSearchSemanticsLabel')}
        </label>
        <input
          id={searchId}
          type="search"
          value={query}
          placeholder={t('daySheetTagSearchHint')}
          autoComplete="off"
          onChange={(event) => setQuery(event.target.value)}
        />
        {searching ? (
          <button type="button" className="btn" onClick={() => setQuery('')}>
            {t('daySheetTagSearchClearTooltip')}
          </button>
        ) : null}
      </div>

      {!searching && recent.length > 0 ? (
        <div className="tag-category">
          <h2 className="tag-category-label" id={recentId}>
            {t('daySheetTagRecentLabel')}
          </h2>
          <div className="chip-row" role="group" aria-labelledby={recentId}>
            {recent.map(({ name, tag }) => (
              <Chip
                key={tag.code}
                label={tag.display}
                selected={false}
                onPress={() => press(tag.code, name)}
                disabled={false}
              />
            ))}
          </div>
        </div>
      ) : null}

      <div className="tag-sections">
        {sections.map(({ category, tags, hasSelection }) => {
          // Search results are all on show; otherwise a hand-set state
          // wins, and an untouched section is open only while it holds
          // something logged.
          const open =
            searching ||
            opened.has(category.name) ||
            (hasSelection && !closed.has(category.name));
          const panelId = `${baseId}-${category.wireName}`;
          return (
            <div key={category.name} className="tag-section">
              <h2 className="tag-section-heading">
                {searching ? (
                  <span className="tag-section-static">{category.label}</span>
                ) : (
                  <button
                    type="button"
                    className="tag-section-toggle"
                    aria-expanded={open}
                    aria-controls={open ? panelId : undefined}
                    onClick={() => setSection(category.name, !open)}
                  >
                    {category.label}
                  </button>
                )}
              </h2>
              {open ? (
                <div
                  id={panelId}
                  className="chip-row tag-section-panel"
                  role="group"
                  aria-label={category.label}
                >
                  {tags.map((tag) => (
                    <Chip
                      key={tag.code}
                      label={tag.display}
                      selected={selected.has(tag.code)}
                      onPress={() => press(tag.code, category.name)}
                      disabled={false}
                    />
                  ))}
                </div>
              ) : null}
            </div>
          );
        })}
        {customTags.length > 0 ? (
          <div className="tag-section">
            <h2 className="tag-section-heading">
              <span className="tag-section-static">{t('daySheetCustomTagsLabel')}</span>
            </h2>
            <div
              className="chip-row tag-section-panel"
              role="group"
              aria-label={t('daySheetCustomTagsLabel')}
            >
              {customTags.map((tag) => (
                <Chip
                  key={tag.code}
                  label={tag.display}
                  selected={selected.has(tag.code)}
                  onPress={() => props.onToggle(tag.code, null)}
                  disabled={false}
                />
              ))}
            </div>
          </div>
        ) : null}
      </div>

      {searching && sections.length === 0 && customTags.length === 0 ? (
        <p className="card-body" role="status">
          {t('webDayTagSearchNoMatches')}
        </p>
      ) : null}
    </>
  );
}
