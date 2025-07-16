"use client"

import React, { useState, useRef, useEffect } from 'react';
import { Play, RotateCcw, Terminal, ChevronRight, AlertCircle, CheckCircle } from 'lucide-react';

interface REPLEntry {
  id: number;
  input: string;
  output?: string;
  error?: string;
  timestamp: Date;
  executionTime?: number;
}

export default function SwiftREPLInterface() {
  const [history, setHistory] = useState<REPLEntry[]>([]);
  const [currentInput, setCurrentInput] = useState('');
  const [isExecuting, setIsExecuting] = useState(false);
  const [isConnected, setIsConnected] = useState(false);
  const [historyIndex, setHistoryIndex] = useState(-1);
  const terminalEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const wsRef = useRef<WebSocket | null>(null);

  const scrollToBottom = () => {
    terminalEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => {
    scrollToBottom();
  }, [history]);

  // WebSocket connection
  useEffect(() => {
    const connectWebSocket = () => {
      const ws = new WebSocket('ws://localhost:8008/inference');

      ws.onopen = () => {
        setIsConnected(true);
        console.log('WebSocket connected to Swift REPL server');
      };

      ws.onclose = (event) => {
        setIsConnected(false);
        console.log('WebSocket disconnected:', event.code, event.reason);
        // Attempt to reconnect after 3 seconds
        setTimeout(connectWebSocket, 3000);
      };

      ws.onerror = (error) => {
        console.error('WebSocket error:', error);
        setIsConnected(false);
      };

      ws.onmessage = (event) => {
        const response = event.data;
        console.log('Received from server:', response);
        // Update the most recent entry with the response
        setHistory(prev => {
          const updated = [...prev];
          const lastEntry = updated[updated.length - 1];
          if (lastEntry && !lastEntry.output && !lastEntry.error) {
            lastEntry.output = response;
            lastEntry.executionTime = Date.now() - lastEntry.timestamp.getTime();
          }
          return updated;
        });
        setIsExecuting(false);
      };

      wsRef.current = ws;
    };

    connectWebSocket();

    return () => {
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, []);

  const executeSwiftCode = async () => {
    if (!currentInput.trim() || !isConnected || !wsRef.current) {
      console.log('Execute blocked:', { hasInput: !!currentInput.trim(), isConnected, hasWs: !!wsRef.current });
      return;
    }

    const entry: REPLEntry = {
      id: Date.now(),
      input: currentInput,
      timestamp: new Date()
    };

    setHistory(prev => [...prev, entry]);
    const codeToSend = currentInput;
    setCurrentInput('');
    setIsExecuting(true);
    setHistoryIndex(-1);

    try {
      // Send the Swift code to the server via WebSocket
      console.log('Sending to WebSocket:', codeToSend);
      wsRef.current.send(codeToSend);
    } catch (error) {
      console.error('WebSocket send error:', error);
      const errorMessage = error instanceof Error ? error.message : 'Connection error';
      setHistory(prev => prev.map(item =>
        item.id === entry.id
          ? { ...item, error: `Connection error: ${errorMessage}`, executionTime: 0 }
          : item
      ));
      setIsExecuting(false);
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      executeSwiftCode();
    } else if (e.key === 'ArrowUp' && e.ctrlKey) {
      e.preventDefault();
      navigateHistory('up');
    } else if (e.key === 'ArrowDown' && e.ctrlKey) {
      e.preventDefault();
      navigateHistory('down');
    }
  };

  const navigateHistory = (direction: 'up' | 'down') => {
    if (history.length === 0) return;

    let newIndex = historyIndex;
    if (direction === 'up') {
      newIndex = historyIndex < history.length - 1 ? historyIndex + 1 : historyIndex;
    } else {
      newIndex = historyIndex > -1 ? historyIndex - 1 : -1;
    }

    setHistoryIndex(newIndex);
    if (newIndex === -1) {
      setCurrentInput('');
    } else {
      setCurrentInput(history[history.length - 1 - newIndex].input);
    }
  };

  const handleReset = () => {
    setHistory([]);
    setCurrentInput('');
    setHistoryIndex(-1);
    inputRef.current?.focus();
  };

  const formatTime = (ms: number) => {
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  return (
    <div className="flex flex-col h-screen bg-white text-gray-900" style={{ fontFamily: 'Avenir Next, -apple-system, BlinkMacSystemFont, sans-serif' }}>
      {/* Header */}
      <div className="bg-white p-4 shadow-sm" style={{ borderBottom: '1px solid #EEEEEE' }}>
        <div className="max-w-6xl mx-auto flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg" style={{ backgroundColor: '#F29F00' }}>
              <Terminal className="text-white" size={24} />
            </div>
            <div>
              <h1 className="text-xl font-bold" style={{ color: '#898989' }}>Swift REPL</h1>
              <p className="text-sm" style={{ color: '#ABABAB' }}>
                Interactive Swift environment • Press Enter to execute • Ctrl+↑/↓ for history
              </p>
            </div>
          </div>
          <div className="text-sm px-3 py-1 rounded-full flex items-center gap-2" style={{ backgroundColor: '#F6F6F6', color: '#ABABAB' }}>
            <div className="w-2 h-2 rounded-full" style={{ backgroundColor: isConnected ? '#5D7CA7' : '#DD4D2A' }}></div>
            <span style={{ color: '#898989' }}>
              {isConnected ? 'Connected' : 'Disconnected'} • {history.length} {history.length === 1 ? 'command' : 'commands'}
            </span>
          </div>
        </div>
      </div>

      {/* Terminal Output */}
      <div className="flex-1 overflow-y-auto p-4 space-y-3">
        <div className="max-w-6xl mx-auto">
          {history.length === 0 && isConnected && (
            <div className="text-center py-12" style={{ color: '#ABABAB' }}>
              <div className="w-16 h-16 rounded-full flex items-center justify-center mx-auto mb-4" style={{ backgroundColor: '#F8CF7F' }}>
                <Terminal size={32} style={{ color: '#F29F00' }} />
              </div>
              <p className="text-lg mb-2" style={{ color: '#898989' }}>Welcome to Swift REPL</p>
              <p className="text-sm" style={{ color: '#ABABAB' }}>Start typing Swift code and press Enter to execute</p>
              <div className="mt-4 text-xs" style={{ color: '#BBBBB' }}>
                <p>Try: <code className="px-2 py-1 rounded" style={{ backgroundColor: '#F6F6F6', fontFamily: 'Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace' }}>print("Hello, Swift!")</code></p>
                <p>Or: <code className="px-2 py-1 rounded" style={{ backgroundColor: '#F6F6F6', fontFamily: 'Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace' }}>let x = 42</code></p>
              </div>
            </div>
          )}

          {!isConnected && (
            <div className="text-center py-12">
              <div className="w-16 h-16 rounded-full flex items-center justify-center mx-auto mb-4" style={{ backgroundColor: '#EEA694' }}>
                <AlertCircle size={32} style={{ color: '#DD4D2A' }} />
              </div>
              <p className="text-lg mb-2" style={{ color: '#898989' }}>Connecting to Swift REPL server...</p>
              <p className="text-sm" style={{ color: '#ABABAB' }}>Make sure the server is running on localhost:8008</p>
            </div>
          )}

          {history.map((entry, index) => (
            <div key={entry.id} className="space-y-2">
              {/* Input */}
              <div className="flex items-start gap-2">
                <span className="font-semibold mt-1 min-w-[3rem]" style={{ color: '#F29F00' }}>
                  {index + 1}:
                </span>
                <ChevronRight className="mt-1" style={{ color: '#CDCDCD' }} size={16} />
                <pre className="flex-1 whitespace-pre-wrap break-words" style={{ color: '#787878', fontFamily: 'Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace' }}>
                  {entry.input}
                </pre>
              </div>

              {/* Output */}
              {entry.output && entry.output.trim() && (
                <div className="flex items-start gap-2 ml-12">
                  <CheckCircle className="mt-1" style={{ color: '#5D7CA7' }} size={14} />
                  <pre className="flex-1 whitespace-pre-wrap break-words rounded p-2 border-l-4" style={{
                    color: '#898989',
                    backgroundColor: '#FFFFFCC',
                    borderColor: '#5D7CA7',
                    fontFamily: 'Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace'
                  }}>
                    {entry.output}
                  </pre>
                </div>
              )}

              {/* Error */}
              {entry.error && (
                <div className="flex items-start gap-2 ml-12">
                  <AlertCircle className="mt-1" style={{ color: '#DD4D2A' }} size={14} />
                  <pre className="flex-1 whitespace-pre-wrap break-words rounded p-2 border-l-4" style={{
                    color: '#DD4D2A',
                    backgroundColor: '#EEA694',
                    borderColor: '#DD4D2A',
                    fontFamily: 'Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace'
                  }}>
                    {entry.error}
                  </pre>
                </div>
              )}

              {/* Execution time */}
              {entry.executionTime && (
                <div className="ml-12 text-xs" style={{ color: '#BBBBB' }}>
                  Executed in {formatTime(entry.executionTime)}
                </div>
              )}
            </div>
          ))}

          {/* Loading indicator */}
          {isExecuting && (
            <div className="flex items-center gap-2 ml-12" style={{ color: '#ABABAB' }}>
              <div className="animate-spin rounded-full h-4 w-4 border-b-2" style={{ borderColor: '#F29F00' }}></div>
              <span>Executing on server...</span>
            </div>
          )}

          <div ref={terminalEndRef} />
        </div>
      </div>

      {/* Input Area */}
      <div className="bg-white p-4 shadow-sm" style={{ borderTop: '1px solid #EEEEEE' }}>
        <div className="max-w-6xl mx-auto">
          <div className="flex items-start gap-3">
            {/* Prompt */}
            <div className="flex items-center gap-2 font-semibold mt-3 min-w-[3rem]" style={{ color: '#F29F00' }}>
              <span>{history.length + 1}:</span>
              <ChevronRight size={16} />
            </div>

            {/* Code Input */}
            <div className="flex-1 relative">
              <textarea
                ref={inputRef}
                value={currentInput}
                onChange={(e) => setCurrentInput(e.target.value)}
                onKeyDown={handleKeyPress}
                placeholder="Enter Swift code..."
                className="w-full p-3 rounded-lg resize-none focus:outline-none focus:ring-2 transition-all duration-200"
                style={{
                  backgroundColor: '#F6F6F6',
                  color: '#787878',
                  border: '1px solid #EEEEEE',
                  fontFamily: 'Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace',
                  minHeight: '48px',
                  maxHeight: '200px'
                }}
                rows={1}
                onInput={(e) => {
                  const target = e.target as HTMLTextAreaElement;
                  target.style.height = 'auto';
                  target.style.height = Math.min(target.scrollHeight, 200) + 'px';
                }}
                autoFocus
              />
            </div>

            {/* Execute Button */}
            <button
              onClick={executeSwiftCode}
              disabled={!currentInput.trim() || isExecuting || !isConnected}
              className="flex-shrink-0 text-white p-3 rounded-lg transition-colors duration-200 shadow-sm h-12 disabled:cursor-not-allowed hover:opacity-90"
              style={{
                backgroundColor: !currentInput.trim() || isExecuting || !isConnected ? '#CDCDCD' : '#F29F00'
              }}
              title={!isConnected ? "Not connected to server" : "Execute Swift code (Enter)"}
            >
              <Play size={20} />
            </button>

            {/* Reset Button */}
            <button
              onClick={handleReset}
              className="flex-shrink-0 text-white p-3 rounded-lg transition-colors duration-200 shadow-sm h-12 hover:opacity-90"
              style={{
                backgroundColor: '#ABABAB'
              }}
              title="Clear history"
            >
              <RotateCcw size={20} />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}