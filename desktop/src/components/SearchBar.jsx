import React, { useState, useRef, useEffect } from 'react';
import { searchStocks } from '../api';

export default function SearchBar({ onSelectStock }) {
  const [keyword, setKeyword] = useState('');
  const [results, setResults] = useState([]);
  const [isOpen, setIsOpen] = useState(false);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState(null);
  const inputRef = useRef(null);
  const dropdownRef = useRef(null);
  const debounceRef = useRef(null);

  useEffect(() => {
    function handleClickOutside(event) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target) &&
          inputRef.current && !inputRef.current.contains(event.target)) {
        setIsOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleSearch = (value) => {
    setKeyword(value);
    setError(null);

    if (debounceRef.current) {
      clearTimeout(debounceRef.current);
    }

    if (!value.trim()) {
      setResults([]);
      setIsOpen(false);
      return;
    }

    debounceRef.current = setTimeout(async () => {
      setSearching(true);
      try {
        const data = await searchStocks(value.trim());
        const list = Array.isArray(data) ? data : (data?.results || []);
        setResults(list);
        setIsOpen(list.length > 0);
      } catch (e) {
        setError(e.message);
        setResults([]);
        setIsOpen(false);
      } finally {
        setSearching(false);
      }
    }, 300);
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Escape') {
      setIsOpen(false);
      inputRef.current?.blur();
    }
  };

  return (
    <div className="search-bar">
      <div className="search-input-wrapper">
        <span className="search-icon">🔍</span>
        <input
          ref={inputRef}
          type="text"
          placeholder="搜索股票代码或名称..."
          value={keyword}
          onChange={(e) => handleSearch(e.target.value)}
          onFocus={() => results.length > 0 && setIsOpen(true)}
          onKeyDown={handleKeyDown}
        />
        {searching && <span className="search-spinner">⏳</span>}
      </div>

      {error && <div className="search-error">{error}</div>}

      {isOpen && results.length > 0 && (
        <div className="search-dropdown" ref={dropdownRef}>
          {results.map((item, idx) => (
            <div
              key={item.code || idx}
              className="search-result-item"
              onClick={() => {
                onSelectStock(item);
                setKeyword(item.code + ' ' + (item.name || ''));
                setIsOpen(false);
              }}
            >
              <span className="result-code">{item.code}</span>
              <span className="result-name">{item.name}</span>
              {item.price !== undefined && (
                <span className="result-price">
                  {typeof item.price === 'number' ? item.price.toFixed(2) : item.price}
                </span>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}