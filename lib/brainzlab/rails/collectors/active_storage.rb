# frozen_string_literal: true

module BrainzLab
  module Rails
    module Collectors
      # Collects Active Storage events for file operation observability
      class ActiveStorage < Base
        def process(event_data)
          case event_data[:name]
          when 'service_upload.active_storage'
            handle_upload(event_data)
          when 'service_download.active_storage', 'service_streaming_download.active_storage'
            handle_download(event_data)
          when 'service_download_chunk.active_storage'
            handle_download_chunk(event_data)
          when 'service_delete.active_storage'
            handle_delete(event_data)
          when 'service_delete_prefixed.active_storage'
            handle_delete_prefixed(event_data)
          when 'service_exist.active_storage'
            handle_exist(event_data)
          when 'service_url.active_storage'
            handle_url(event_data)
          when 'service_update_metadata.active_storage'
            handle_update_metadata(event_data)
          when 'preview.active_storage'
            handle_preview(event_data)
          when 'transform.active_storage'
            handle_transform(event_data)
          when 'analyze.active_storage'
            handle_analyze(event_data)
          end
        end

        private

        def handle_upload(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          service = payload[:service]
          checksum = payload[:checksum]
          duration_ms = event_data[:duration_ms]

          # === PULSE: Upload span ===
          send_to_pulse(event_data, {
            name: "storage.upload",
            category: 'storage.upload',
            attributes: {
              key: key,
              service: service,
              checksum: checksum
            }
          })

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.storage.uploads', 1, {
            service: service
          })
          send_to_flux(:timing, 'rails.storage.upload_ms', duration_ms, {
            service: service
          })

          # === RECALL: Log upload ===
          send_to_recall(:info, "File uploaded", {
            key: key,
            service: service,
            duration_ms: duration_ms
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Storage upload: #{key}",
            category: 'storage.upload',
            level: :info,
            data: {
              key: key,
              service: service,
              duration_ms: duration_ms
            }
          )
        end

        def handle_download(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          service = payload[:service]
          duration_ms = event_data[:duration_ms]
          streaming = event_data[:name].include?('streaming')

          # === PULSE: Download span ===
          send_to_pulse(event_data, {
            name: streaming ? "storage.stream" : "storage.download",
            category: 'storage.download',
            attributes: {
              key: key,
              service: service,
              streaming: streaming
            }
          })

          # === FLUX: Metrics ===
          metric_name = streaming ? 'rails.storage.streams' : 'rails.storage.downloads'
          send_to_flux(:increment, metric_name, 1, { service: service })
          send_to_flux(:timing, 'rails.storage.download_ms', duration_ms, {
            service: service,
            streaming: streaming
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Storage #{streaming ? 'stream' : 'download'}: #{key}",
            category: 'storage.download',
            level: :debug,
            data: {
              key: key,
              service: service,
              duration_ms: duration_ms
            }
          )
        end

        def handle_download_chunk(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          service = payload[:service]
          range = payload[:range]

          # === FLUX: Chunk metrics ===
          send_to_flux(:increment, 'rails.storage.chunks', 1, {
            service: service
          })

          # === REFLEX: Breadcrumb (debug level for chunks) ===
          add_breadcrumb(
            "Storage chunk: #{key}",
            category: 'storage.chunk',
            level: :debug,
            data: {
              key: key,
              range: range.to_s
            }
          )
        end

        def handle_delete(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          service = payload[:service]
          duration_ms = event_data[:duration_ms]

          # === PULSE: Delete span ===
          send_to_pulse(event_data, {
            name: "storage.delete",
            category: 'storage.delete',
            attributes: {
              key: key,
              service: service
            }
          })

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.storage.deletes', 1, {
            service: service
          })

          # === RECALL: Log deletion ===
          send_to_recall(:info, "File deleted", {
            key: key,
            service: service,
            duration_ms: duration_ms
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Storage delete: #{key}",
            category: 'storage.delete',
            level: :info,
            data: { key: key, service: service }
          )
        end

        def handle_delete_prefixed(event_data)
          payload = event_data[:payload]
          prefix = payload[:prefix]
          service = payload[:service]

          # === FLUX: Bulk delete metrics ===
          send_to_flux(:increment, 'rails.storage.bulk_deletes', 1, {
            service: service
          })

          # === RECALL: Log bulk deletion ===
          send_to_recall(:info, "Bulk file deletion", {
            prefix: prefix,
            service: service
          })
        end

        def handle_exist(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          service = payload[:service]
          exist = payload[:exist]

          # === FLUX: Existence check metrics ===
          send_to_flux(:increment, 'rails.storage.exist_checks', 1, {
            service: service,
            exists: exist
          })
        end

        def handle_url(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          service = payload[:service]
          duration_ms = event_data[:duration_ms]

          # === FLUX: URL generation metrics ===
          send_to_flux(:increment, 'rails.storage.url_generations', 1, {
            service: service
          })
          send_to_flux(:timing, 'rails.storage.url_ms', duration_ms, {
            service: service
          })
        end

        def handle_update_metadata(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          service = payload[:service]

          # === FLUX: Metadata update metrics ===
          send_to_flux(:increment, 'rails.storage.metadata_updates', 1, {
            service: service
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Storage metadata update: #{key}",
            category: 'storage.metadata',
            level: :debug,
            data: {
              key: key,
              content_type: payload[:content_type],
              disposition: payload[:disposition]
            }
          )
        end

        def handle_preview(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          duration_ms = event_data[:duration_ms]

          # === PULSE: Preview generation span ===
          send_to_pulse(event_data, {
            name: "storage.preview",
            category: 'storage.preview',
            attributes: { key: key }
          })

          # === FLUX: Preview metrics ===
          send_to_flux(:increment, 'rails.storage.previews', 1)
          send_to_flux(:timing, 'rails.storage.preview_ms', duration_ms)
        end

        def handle_transform(event_data)
          payload = event_data[:payload]
          duration_ms = event_data[:duration_ms]

          # === PULSE: Transform span ===
          send_to_pulse(event_data, {
            name: "storage.transform",
            category: 'storage.transform',
            attributes: {}
          })

          # === FLUX: Transform metrics ===
          send_to_flux(:increment, 'rails.storage.transforms', 1)
          send_to_flux(:timing, 'rails.storage.transform_ms', duration_ms)
        end

        def handle_analyze(event_data)
          payload = event_data[:payload]
          analyzer = payload[:analyzer]
          duration_ms = event_data[:duration_ms]

          # === PULSE: Analyze span ===
          send_to_pulse(event_data, {
            name: "storage.analyze.#{analyzer}",
            category: 'storage.analyze',
            attributes: { analyzer: analyzer }
          })

          # === FLUX: Analyze metrics ===
          send_to_flux(:increment, 'rails.storage.analyzes', 1, {
            analyzer: analyzer
          })
          send_to_flux(:timing, 'rails.storage.analyze_ms', duration_ms, {
            analyzer: analyzer
          })
        end
      end
    end
  end
end
