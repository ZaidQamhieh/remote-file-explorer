import { create } from 'zustand';

import {
  SavedSearches,
  addPin,
  bookmarksList,
  favoritesList,
  pinsList,
  recentSearchesList,
  recordSearch,
  removeBookmark,
  removePin,
  toggleFavorite,
  upsertBookmark,
  type Bookmark,
  type Favorite,
  type Pin,
  type SavedSearch,
} from '../core/storage/collections';
import { keyValue, listingCache } from '../services';

const favs = favoritesList(keyValue);
const marks = bookmarksList(keyValue);
const pinsStore = pinsList(keyValue);
const recents = recentSearchesList(keyValue);
const saved = new SavedSearches(keyValue);

type S = {
  loaded: boolean;
  favorites: Favorite[];
  bookmarks: Bookmark[];
  pins: Pin[];
  recentSearches: string[];
  savedSearches: SavedSearch[];
  load(): Promise<void>;
  toggleFavorite(f: Favorite): Promise<void>;
  removeFavorite(hostId: string, path: string): Promise<void>;
  addBookmark(b: Bookmark): Promise<void>;
  removeBookmark(hostId: string, path: string): Promise<void>;
  pin(hostId: string, path: string): Promise<void>;
  unpin(hostId: string, path: string): Promise<void>;
  recordSearch(q: string): Promise<void>;
  removeRecentSearch(q: string): Promise<void>;
  clearRecentSearches(): Promise<void>;
  addSavedSearch(s: SavedSearch): Promise<void>;
  removeSavedSearch(name: string): Promise<void>;
};

/** Favorites, bookmarks, offline pins and searches: persisted first, then mirrored in memory. Keys/encodings match the Flutter app. */
export const useCollections = create<S>((set, get) => ({
  loaded: false,
  favorites: [],
  bookmarks: [],
  pins: [],
  recentSearches: [],
  savedSearches: [],
  async load() {
    const [favorites, bookmarks, pins, recentSearches, savedSearches] = await Promise.all([favs.load(), marks.load(), pinsStore.load(), recents.load(), saved.load()]);
    set({ favorites, bookmarks, pins, recentSearches, savedSearches, loaded: true });
  },
  async toggleFavorite(f) {
    const next = toggleFavorite(get().favorites, f);
    await favs.save(next);
    set({ favorites: next });
  },
  async removeFavorite(hostId, path) {
    const next = get().favorites.filter((f) => !(f.hostId === hostId && f.path === path));
    await favs.save(next);
    set({ favorites: next });
  },
  async addBookmark(b) {
    const next = upsertBookmark(get().bookmarks, b);
    await marks.save(next);
    set({ bookmarks: next });
  },
  async removeBookmark(hostId, path) {
    const next = removeBookmark(get().bookmarks, hostId, path);
    await marks.save(next);
    set({ bookmarks: next });
  },
  async pin(hostId, path) {
    const next = addPin(get().pins, { hostId, remotePath: path });
    await pinsStore.save(next);
    set({ pins: next });
    listingCache.syncPinned(hostId, next.filter((p) => p.hostId === hostId).map((p) => p.remotePath));
  },
  async unpin(hostId, path) {
    const next = removePin(get().pins, hostId, path);
    await pinsStore.save(next);
    set({ pins: next });
    listingCache.syncPinned(hostId, next.filter((p) => p.hostId === hostId).map((p) => p.remotePath));
  },
  async recordSearch(q) {
    const next = recordSearch(get().recentSearches, q);
    await recents.save(next);
    set({ recentSearches: next });
  },
  async removeRecentSearch(q) {
    const next = get().recentSearches.filter((s) => s !== q);
    await recents.save(next);
    set({ recentSearches: next });
  },
  async clearRecentSearches() {
    await recents.save([]);
    set({ recentSearches: [] });
  },
  async addSavedSearch(s) {
    const next = [s, ...get().savedSearches];
    await saved.save(next);
    set({ savedSearches: next });
  },
  async removeSavedSearch(name) {
    const next = get().savedSearches.filter((s) => s.name !== name);
    await saved.save(next);
    set({ savedSearches: next });
  },
}));

export const isPinned = (pins: Pin[], hostId: string, path: string) => pins.some((p) => p.hostId === hostId && p.remotePath === path);
