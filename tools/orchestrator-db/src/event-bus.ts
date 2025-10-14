import { EventEmitter } from "node:events";
import type { EventBus, EventListener, OrchestratorEvent } from "./types.js";

const CHANNEL = "event";

export class OrchestratorEventBus implements EventBus {
  private readonly emitter: EventEmitter;

  constructor(emitter?: EventEmitter) {
    this.emitter = emitter ?? new EventEmitter();
    this.emitter.setMaxListeners(100);
  }

  publish(event: OrchestratorEvent): void {
    this.emitter.emit(CHANNEL, event);
  }

  subscribe(listener: EventListener): () => void {
    this.emitter.on(CHANNEL, listener);
    return () => {
      this.emitter.off(CHANNEL, listener);
    };
  }

  get raw(): EventEmitter {
    return this.emitter;
  }
}

export function createEventBus(): OrchestratorEventBus {
  return new OrchestratorEventBus();
}
