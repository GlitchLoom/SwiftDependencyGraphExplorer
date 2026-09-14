enum MermaidHTMLTemplate {
    static let source = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <script src="mermaid.min.js"></script>
      <style>
        html, body, #viewport { width: 100%; height: 100%; margin: 0; overflow: hidden; background: transparent; }
        #viewport { position: relative; cursor: grab; touch-action: none; }
        #viewport.dragging { cursor: grabbing; }
        #canvas { width: 100%; height: 100%; display: grid; place-items: center; transform-origin: center center; }
        #diagram svg { display: block; max-width: none; max-height: none; }
        #diagram svg.sdge-path-active .node,
        #diagram svg.sdge-path-active .edgePaths path,
        #diagram svg.sdge-path-active .edgeLabel {
          opacity: 0.18;
          transition: opacity 120ms ease, stroke 120ms ease, stroke-width 120ms ease;
        }
        #diagram svg.sdge-path-active .sdge-node-path,
        #diagram svg.sdge-path-active .sdge-node-path *,
        #diagram svg.sdge-path-active .sdge-edge-path,
        #diagram svg.sdge-path-active .sdge-edge-label,
        #diagram svg.sdge-path-active .sdge-edge-label * {
          opacity: 1 !important;
        }
        #diagram .sdge-clickable-node { cursor: pointer; }
        #diagram .sdge-node-path rect,
        #diagram .sdge-node-path polygon,
        #diagram .sdge-node-path ellipse,
        #diagram .sdge-node-path circle {
          stroke: #0a84ff !important;
          stroke-width: 3px !important;
        }
        #diagram .sdge-root-node rect,
        #diagram .sdge-root-node polygon,
        #diagram .sdge-root-node ellipse,
        #diagram .sdge-root-node circle {
          fill: rgba(10, 132, 255, 0.14) !important;
        }
        #diagram .sdge-target-node rect,
        #diagram .sdge-target-node polygon,
        #diagram .sdge-target-node ellipse,
        #diagram .sdge-target-node circle {
          fill: rgba(48, 209, 88, 0.18) !important;
        }
        #diagram .sdge-edge-path {
          stroke: #0a84ff !important;
          stroke-width: 3px !important;
        }
        #diagram .sdge-selected-node rect,
        #diagram .sdge-selected-node polygon,
        #diagram .sdge-selected-node ellipse,
        #diagram .sdge-selected-node circle {
          stroke: #bf5af2 !important;
          stroke-width: 4px !important;
          fill: rgba(191, 90, 242, 0.16) !important;
        }
        #diagram svg.sdge-path-active .sdge-selected-node,
        #diagram svg.sdge-path-active .sdge-selected-node * {
          opacity: 1 !important;
        }
        #diagram .sdge-edge-marker {
          fill: rgba(255, 255, 255, 0.92);
          stroke: #8e8e93;
          stroke-width: 1.5px;
          cursor: pointer;
        }
        #diagram .sdge-edge-marker:hover {
          stroke: #0a84ff;
          stroke-width: 2px;
        }
        .sdge-edge-tooltip {
          position: absolute;
          z-index: 10;
          max-width: 240px;
          padding: 6px 8px;
          border-radius: 6px;
          background: rgba(28, 28, 30, 0.92);
          color: #ffffff;
          font: 11px -apple-system, BlinkMacSystemFont, sans-serif;
          line-height: 1.4;
          box-shadow: 0 2px 8px rgba(0, 0, 0, 0.25);
          pointer-events: none;
          white-space: nowrap;
        }
      </style>
    </head>
    <body>
      <div id="viewport"><div id="canvas"><div id="diagram"></div></div></div>
      <script>
        const viewport = document.getElementById('viewport');
        const canvas = document.getElementById('canvas');
        const diagram = document.getElementById('diagram');
        const minimumZoom = 0.1;
        const maximumZoom = 30;
        const dragThreshold = 4;
        let scale = 1;
        let offsetX = 0;
        let offsetY = 0;
        let pointer = null;
        const activeRender = { generation: null, source: null };
        const renderedDiagram = { generation: null, source: null };
        let graphInteraction = null;
        let edgeGroups = [];
        let activeTooltip = null;
        let activeEdgeGroupIndex = null;

        mermaid.initialize({
          startOnLoad: false,
          securityLevel: 'strict',
          flowchart: {
            htmlLabels: false,
            nodeSpacing: 80,
            rankSpacing: 110,
            curve: 'basis'
          }
        });

        function post(message) {
          window.webkit.messageHandlers.mermaidRenderer.postMessage(message);
        }

        function applyTransform() {
          canvas.style.transform = `translate(${offsetX}px, ${offsetY}px) scale(${scale})`;
        }

        function setZoom(nextScale) {
          scale = Math.max(minimumZoom, Math.min(maximumZoom, nextScale));
          applyTransform();
        }

        window.zoomIn = () => setZoom(scale * 1.25);
        window.zoomOut = () => setZoom(scale / 1.25);
        window.resetZoom = () => {
          scale = 1;
          offsetX = 0;
          offsetY = 0;
          applyTransform();
        };
        window.clearPathHighlight = () => {
          const svg = diagram.querySelector('svg');
          if (!svg) return;
          svg.classList.remove('sdge-path-active');
          diagram.querySelectorAll('.sdge-node-path, .sdge-root-node, .sdge-target-node, .sdge-edge-path, .sdge-edge-label')
            .forEach(element => {
              element.classList.remove(
                'sdge-node-path',
                'sdge-root-node',
                'sdge-target-node',
                'sdge-edge-path',
                'sdge-edge-label'
              );
            });
        };
        window.fitToScreen = () => {
          const svg = diagram.querySelector('svg');
          if (!svg) return;
          const box = svg.getBBox();
          if (!box.width || !box.height) return;
          const view = viewport.getBoundingClientRect();
          scale = Math.max(minimumZoom, Math.min(maximumZoom, Math.min(view.width / box.width, view.height / box.height) * 0.9));
          offsetX = 0;
          offsetY = 0;
          applyTransform();
        };
        window.currentSVG = (expectedSource, expectedGeneration) => {
          if (expectedSource !== undefined &&
              (renderedDiagram.source !== expectedSource || renderedDiagram.generation !== expectedGeneration)) {
            return null;
          }
          return diagram.querySelector('svg')?.outerHTML ?? '';
        };
        function nodeElement(mermaidID) {
          return diagram.querySelector(`[id^="flowchart-${mermaidID}-"]`);
        }

        function nodeNameForElement(element) {
          if (!graphInteraction || !element) return null;
          const nodeContainer = element.closest('.node');
          if (!nodeContainer) return null;
          const node = graphInteraction.nodes.find(candidate => {
            const renderedNode = nodeElement(candidate.mermaidID);
            return renderedNode === nodeContainer;
          });
          return node?.name ?? null;
        }

        function edgePrefixSelectors(sourceMermaidID, targetMermaidID, attribute) {
          // Mermaid has used both "L_source_target_n" (current bundled version) and
          // "L-source-target-n" (older versions) for edge/label element ids.
          return [
            `${attribute}^="L_${sourceMermaidID}_${targetMermaidID}_"`,
            `${attribute}^="L-${sourceMermaidID}-${targetMermaidID}-"`
          ];
        }

        function edgeElements(sourceMermaidID, targetMermaidID) {
          const idSelectors = edgePrefixSelectors(sourceMermaidID, targetMermaidID, 'id')
            .map(condition => `path[${condition}]`);
          const dataIdSelectors = edgePrefixSelectors(sourceMermaidID, targetMermaidID, 'data-id')
            .map(condition => `[${condition}]`);
          const directPaths = Array.from(diagram.querySelectorAll(idSelectors.join(', ')));
          const dataIdGroups = Array.from(diagram.querySelectorAll(dataIdSelectors.join(', ')));
          const groupPaths = dataIdGroups.flatMap(group => Array.from(group.querySelectorAll('path, line, polyline')));
          return [...new Set([...directPaths, ...groupPaths])];
        }

        function labelElements(sourceMermaidID, targetMermaidID) {
          const dataIdSelectors = edgePrefixSelectors(sourceMermaidID, targetMermaidID, 'data-id')
            .map(condition => `[${condition}]`);
          return Array.from(diagram.querySelectorAll(dataIdSelectors.join(', ')))
            .filter(element => !element.matches('path'));
        }

        function escapeHTML(value) {
          const container = document.createElement('div');
          container.textContent = value;
          return container.innerHTML;
        }

        function detailLine(detail) {
          return detail.memberName ? `${detail.relationship}: ${detail.memberName}` : detail.relationship;
        }

        function midpointOf(elements) {
          for (const element of elements) {
            if (typeof element.getPointAtLength === 'function' && typeof element.getTotalLength === 'function') {
              const length = element.getTotalLength();
              if (length > 0) return { point: element.getPointAtLength(length / 2), reference: element };
            }
          }
          const first = elements[0];
          if (!first || typeof first.getBBox !== 'function') return null;
          const box = first.getBBox();
          return { point: { x: box.x + box.width / 2, y: box.y + box.height / 2 }, reference: first };
        }

        function hideEdgeTooltip() {
          if (activeTooltip) {
            activeTooltip.remove();
            activeTooltip = null;
          }
          activeEdgeGroupIndex = null;
        }

        function showEdgeTooltip(groupIndex, clientX, clientY) {
          hideEdgeTooltip();
          const group = edgeGroups[groupIndex];
          if (!group) return;

          const tooltip = document.createElement('div');
          tooltip.className = 'sdge-edge-tooltip';
          tooltip.innerHTML = group.details.map(detail => `<div>${escapeHTML(detailLine(detail))}</div>`).join('');
          viewport.appendChild(tooltip);

          const bounds = viewport.getBoundingClientRect();
          const left = Math.min(Math.max(clientX - bounds.left, 4), Math.max(4, bounds.width - tooltip.offsetWidth - 4));
          const top = Math.min(Math.max(clientY - bounds.top - tooltip.offsetHeight - 12, 4), Math.max(4, bounds.height - tooltip.offsetHeight - 4));
          tooltip.style.left = `${left}px`;
          tooltip.style.top = `${top}px`;

          activeTooltip = tooltip;
          activeEdgeGroupIndex = groupIndex;
        }

        function clearEdgeMarkers() {
          diagram.querySelectorAll('.sdge-edge-marker').forEach(element => element.remove());
          edgeGroups = [];
          hideEdgeTooltip();
        }

        function renderEdgeMarkers() {
          clearEdgeMarkers();
          const svg = diagram.querySelector('svg');
          if (!svg || !graphInteraction) return;

          const groupsByPair = new Map();
          graphInteraction.edges.forEach(edge => {
            const key = `${edge.sourceMermaidID}->${edge.targetMermaidID}`;
            if (!groupsByPair.has(key)) {
              groupsByPair.set(key, {
                sourceMermaidID: edge.sourceMermaidID,
                targetMermaidID: edge.targetMermaidID,
                details: []
              });
            }
            groupsByPair.get(key).details.push({ relationship: edge.relationship, memberName: edge.memberName });
          });

          groupsByPair.forEach(group => {
            const elements = edgeElements(group.sourceMermaidID, group.targetMermaidID);
            const midpoint = midpointOf(elements);
            if (!midpoint) return;

            const marker = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
            marker.setAttribute('cx', String(midpoint.point.x));
            marker.setAttribute('cy', String(midpoint.point.y));
            marker.setAttribute('r', '6');
            marker.setAttribute('class', 'sdge-edge-marker');
            marker.dataset.edgeGroupIndex = String(edgeGroups.length);
            // Append into the same coordinate space as the reference path (its parent),
            // not the root <svg>, since getPointAtLength() is local to that space and
            // mermaid applies its own layout transform on an ancestor <g>.
            const anchor = midpoint.reference.parentNode || svg;
            anchor.appendChild(marker);
            edgeGroups.push(group);
          });
        }

        function edgeGroupIndexForElement(element) {
          const marker = element && typeof element.closest === 'function' ? element.closest('.sdge-edge-marker') : null;
          if (!marker) return null;
          const index = Number(marker.dataset.edgeGroupIndex);
          return Number.isNaN(index) ? null : index;
        }

        function findPath(targetName) {
          if (!graphInteraction || !graphInteraction.rootNodeName) return null;
          const rootName = graphInteraction.rootNodeName;
          if (rootName === targetName) {
            return { nodeNames: [rootName], edges: [] };
          }

          const outgoing = new Map();
          graphInteraction.edges.forEach(edge => {
            if (!outgoing.has(edge.sourceName)) outgoing.set(edge.sourceName, []);
            outgoing.get(edge.sourceName).push(edge);
          });

          const queue = [rootName];
          const visited = new Set([rootName]);
          const parentEdge = new Map();

          while (queue.length > 0) {
            const current = queue.shift();
            for (const edge of outgoing.get(current) ?? []) {
              if (visited.has(edge.targetName)) continue;
              visited.add(edge.targetName);
              parentEdge.set(edge.targetName, edge);
              if (edge.targetName === targetName) {
                const edges = [];
                const nodeNames = [targetName];
                let cursor = targetName;
                while (cursor !== rootName) {
                  const step = parentEdge.get(cursor);
                  if (!step) return null;
                  edges.unshift(step);
                  cursor = step.sourceName;
                  nodeNames.unshift(cursor);
                }
                return { nodeNames, edges };
              }
              queue.push(edge.targetName);
            }
          }

          return null;
        }

        function collectIncomingEdges(targetName) {
          if (!graphInteraction) return [];
          const collected = [];
          const queue = [targetName];
          const visitedNodes = new Set([targetName]);
          const visitedEdges = new Set();

          while (queue.length > 0) {
            const current = queue.shift();
            graphInteraction.edges
              .filter(edge => edge.targetName === current)
              .forEach(edge => {
                const edgeKey = `${edge.sourceName}->${edge.targetName}:${edge.relationship}`;
                if (visitedEdges.has(edgeKey)) return;
                visitedEdges.add(edgeKey);
                collected.push(edge);
                if (!visitedNodes.has(edge.sourceName)) {
                  visitedNodes.add(edge.sourceName);
                  queue.push(edge.sourceName);
                }
              });
          }

          return collected;
        }

        function applyPathHighlight(targetName) {
          const svg = diagram.querySelector('svg');
          if (!svg || !graphInteraction) return;
          window.clearPathHighlight();

          const nodeByName = new Map(graphInteraction.nodes.map(node => [node.name, node]));
          const rootPath = findPath(targetName) ?? { nodeNames: [targetName], edges: [] };
          const incomingEdges = collectIncomingEdges(targetName);
          const highlightEdges = [...new Map(
            [...rootPath.edges, ...incomingEdges].map(edge => [
              `${edge.sourceName}->${edge.targetName}:${edge.relationship}`,
              edge
            ])
          ).values()];
          const highlightNodeNames = new Set(rootPath.nodeNames);
          highlightEdges.forEach(edge => {
            highlightNodeNames.add(edge.sourceName);
            highlightNodeNames.add(edge.targetName);
          });

          svg.classList.add('sdge-path-active');
          highlightNodeNames.forEach(nodeName => {
            const node = nodeByName.get(nodeName);
            const element = node ? nodeElement(node.mermaidID) : null;
            if (!element) return;
            element.classList.add('sdge-node-path');
            if (nodeName === graphInteraction.rootNodeName) element.classList.add('sdge-root-node');
            if (nodeName === targetName) element.classList.add('sdge-target-node');
          });

          highlightEdges.forEach(edge => {
            edgeElements(edge.sourceMermaidID, edge.targetMermaidID)
              .forEach(element => element.classList.add('sdge-edge-path'));
            labelElements(edge.sourceMermaidID, edge.targetMermaidID)
              .forEach(element => element.classList.add('sdge-edge-label'));
          });
        }

        window.setGraphInteraction = payload => {
          graphInteraction = payload;
          window.clearPathHighlight();
          hideEdgeTooltip();
          if (!graphInteraction) {
            clearEdgeMarkers();
            return;
          }

          graphInteraction.nodes.forEach(node => {
            const element = nodeElement(node.mermaidID);
            if (!element) return;
            element.classList.add('sdge-clickable-node');
            element.classList.toggle('sdge-selected-node', node.name === graphInteraction.rootNodeName);
          });

          renderEdgeMarkers();
        };

        window.renderMermaid = async (source, generation, interaction) => {
          activeRender.generation = generation;
          activeRender.source = source;
          try {
            const id = `mermaid-${Date.now()}`;
            const rendered = await mermaid.render(id, source);
            if (activeRender.generation !== generation || activeRender.source !== source) return;
            diagram.innerHTML = rendered.svg;
            renderedDiagram.generation = generation;
            renderedDiagram.source = source;
            window.setGraphInteraction(interaction);
            window.resetZoom();
            post({ type: 'rendered', generation, source, svg: window.currentSVG(source, generation) });
          } catch (error) {
            if (activeRender.generation !== generation || activeRender.source !== source) return;
            diagram.innerHTML = '';
            renderedDiagram.generation = null;
            renderedDiagram.source = null;
            post({ type: 'error', generation, source, message: String(error) });
          }
        };

        viewport.addEventListener('pointerdown', event => {
          const targetNodeName = nodeNameForElement(event.target);
          const edgeGroupIndex = targetNodeName ? null : edgeGroupIndexForElement(event.target);
          pointer = {
            id: event.pointerId,
            x: event.clientX,
            y: event.clientY,
            startX: event.clientX,
            startY: event.clientY,
            targetNodeName,
            edgeGroupIndex,
            didDrag: false
          };
          viewport.setPointerCapture(event.pointerId);
        });
        viewport.addEventListener('pointermove', event => {
          if (!pointer || event.pointerId !== pointer.id) return;
          const totalDeltaX = event.clientX - pointer.startX;
          const totalDeltaY = event.clientY - pointer.startY;
          if (!pointer.didDrag && Math.hypot(totalDeltaX, totalDeltaY) >= dragThreshold) {
            pointer.didDrag = true;
            viewport.classList.add('dragging');
          }
          if (!pointer.didDrag) return;

          offsetX += event.clientX - pointer.x;
          offsetY += event.clientY - pointer.y;
          pointer.x = event.clientX;
          pointer.y = event.clientY;
          applyTransform();
        });
        // Detecting the second click ourselves (rather than listening for the native
        // 'dblclick' mouse event) avoids relying on how WebKit retargets synthetic mouse
        // events after viewport.setPointerCapture() above -- we already know exactly which
        // node each pointerup landed on from our own pointer-event handling.
        let lastNodeClick = { name: null, time: 0 };
        const doubleClickThresholdMs = 400;

        function finishPointer(event) {
          if (!pointer || event.pointerId !== pointer.id) return;
          if (!pointer.didDrag) {
            if (pointer.targetNodeName) {
              hideEdgeTooltip();
              const isDoubleClick = lastNodeClick.name === pointer.targetNodeName &&
                (event.timeStamp - lastNodeClick.time) <= doubleClickThresholdMs;
              if (isDoubleClick) {
                lastNodeClick = { name: null, time: 0 };
                post({ type: 'nodeActivated', name: pointer.targetNodeName });
              } else {
                lastNodeClick = { name: pointer.targetNodeName, time: event.timeStamp };
                applyPathHighlight(pointer.targetNodeName);
              }
            } else if (pointer.edgeGroupIndex !== null && pointer.edgeGroupIndex !== undefined) {
              lastNodeClick = { name: null, time: 0 };
              if (activeEdgeGroupIndex === pointer.edgeGroupIndex) {
                hideEdgeTooltip();
              } else {
                showEdgeTooltip(pointer.edgeGroupIndex, event.clientX, event.clientY);
              }
            } else {
              lastNodeClick = { name: null, time: 0 };
              hideEdgeTooltip();
              window.clearPathHighlight();
            }
          }
          pointer = null;
          viewport.classList.remove('dragging');
        }
        viewport.addEventListener('pointerup', finishPointer);
        viewport.addEventListener('pointercancel', finishPointer);
        viewport.addEventListener('wheel', event => {
          event.preventDefault();
          setZoom(scale * (event.deltaY < 0 ? 1.1 : 1 / 1.1));
        }, { passive: false });
      </script>
    </body>
    </html>
    """
}
