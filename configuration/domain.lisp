(in-package :mu-cl-resources)

;;;;; product groups

;; Examples resources

;; (define-resource taxonomy ()
;;   :class (s-prefix "mt:Taxonomy")
;;   :properties `((:name :string ,(s-prefix "mt:name"))
;;                 (:description :string ,(s-prefix "dc:description")))
;;   :resource-base (s-url "http://mapping-tool.sem.tenforce.com/taxonomies/")
;;   :has-many `((topic :via ,(s-prefix "mt:taxonomyTopic")
;;                      :as "topics"))
;;   :on-path "taxonomies")

;; (define-resource topic ()
;;   :class (s-prefix "mt:CursoryTopic")
;;   :properties `((:name :string ,(s-prefix "mt:name"))
;;                 (:description :string ,(s-prefix "dc:description")))
;;   :resource-base (s-url "http://mapping-tool.sem.tenforce.com/topics/")
;;   :has-many `((topic :via ,(s-prefix "mt:topic")
;;                      :as "topics")
;;               (mapping :via ,(s-prefix "mt:mapping")
;;                        :as "mappings"))
;;   :has-one `((taxonomy :via ,(s-prefix "mt:taxonomyTopic")
;;                        :inverse t
;;                        :as "taxonomy"))
;;   :on-path "topics")

;; (define-resource mapping ()
;;   :class (s-prefix "mt:Mapping")
;;   :has-many `((topic :via ,(s-prefix "mt:maps")
;;                      :as "topics"))
;;   :resource-base (s-url "http://mapping-tool.sem.tenforce.com/mappings/")
;;   :on-path "mappings")
              
(define-resource catalog ()
  :class (s-prefix "dcat:Catalog")
  :properties `((:title :string ,(s-prefix "dct:title"))
                (:description :string ,(s-prefix "dct:description"))
                (:issued :string ,(s-prefix "dct:issued"))
                (:modified :string ,(s-prefix "dct:modified"))
                (:language :string ,(s-prefix "dct:language"))
                (:license :string ,(s-prefix "dct:license"))
                (:rights :string ,(s-prefix "dct:rights"))
                (:spatial :string ,(s-prefix "dct:spatial"))
                (:homepage :string ,(s-prefix "foaf:homepage")))
  :has-one `((publisher :via ,(s-prefix "dct:publisher")
                        :as "publisher")
             (concept-scheme :via ,(s-prefix "dcat:themeTaxonomy")
                             :as "theme-taxonomy")
             (catalog-record :via ,(s-prefix "dcat:record")
                             :as "record"))
  :has-many `((dataset :via ,(s-prefix "dcat:dataset")
                       :as "datasets"))
  :resource-base (s-url "http://your-data-stories.eu/catalogs/")
  :authorization (list :show (s-prefix "auth:show")
                       :update (s-prefix "auth:update")
                       :create (s-prefix "auth:create")
                       :delete (s-prefix "auth:delete"))
  :on-path "catalogs")

(define-resource dataset ()
  :class (s-prefix "dcat:Dataset")
  :properties `((:title :string ,(s-prefix "dct:title"))
                (:description :string ,(s-prefix "dct:description"))
                (:issued :string ,(s-prefix "dct:issued"))
                (:modified :string ,(s-prefix "dct:modified"))
                (:identifier :string ,(s-prefix "dct:identifier"))
                (:keyword :string ,(s-prefix "dct:keyword"))
                (:language :string ,(s-prefix "dct:language"))
                (:contact-point :string ,(s-prefix "dct:contactPoint"))
                (:temporal :string ,(s-prefix "dct:temporal"))
                (:accrual-periodicity :string ,(s-prefix "dct:accrualPeriodicity"))
                (:landing-page :string ,(s-prefix "dcat:landingPage")))
  :has-one `((publisher :via ,(s-prefix "dct:publisher")
                        :as "publisher")
             (catalog :via ,(s-prefix "dcat:dataset")
                      :inverse t
                      :as "catalog")
             (catalog-record :via ,(s-prefix "foaf:primaryTopic")
                             :inverse t
                             :as "primary-topic"))
  :has-many `((concept :via ,(s-prefix "dcat:theme")
                       :as "themes")
              (distribution :via ,(s-prefix "dcat:distribution")
                            :as "distributions"))
  :resource-base (s-url "http://your-data-stories.eu/datasets/")
  :on-path "datasets")

(define-resource distribution ()
  :class (s-prefix "dcat:Distribution")
  :properties `((:title :string ,(s-prefix "dct:title"))
                (:description :string ,(s-prefix "dct:description"))
                (:issued :string ,(s-prefix "dct:issued"))
                (:modified :string ,(s-prefix "dct:modified"))
                (:license :string ,(s-prefix "dct:license"))
                (:rights :string ,(s-prefix "dct:rights"))
                (:access-url :string ,(s-prefix "dcat:accessURL"))
                (:download-url :string ,(s-prefix "dcat:downloadURL"))
                (:media-type :string ,(s-prefix "dcat:mediaType"))
                (:byte-size :string ,(s-prefix "dcat:byteSize")))
  :has-one `((dataset :via ,(s-prefix "dcat:distribution")
                      :inverse t
                      :as "dataset")
             (format :via ,(s-prefix "dct:format")
                     :as "format"))
  :resource-base (s-url "http://your-data-stories.eu/distributions/")
  :on-path "distributions")

(define-resource catalog-record ()
  :class (s-prefix "dcat:CatalogRecord")
  :properties `((:title :string ,(s-prefix "dct:title"))
                (:description :string ,(s-prefix "dct:description"))
                (:issued :string ,(s-prefix "dct:issued"))
                (:modified :string ,(s-prefix "dct:modified")))
  :has-one `((catalog :via ,(s-prefix "dcat:record")
                      :inverse t
                      :as "catalog")
             (dataset :via ,(s-prefix "foaf:primaryTopic")
                      :as "primary-topic"))
  :resource-base (s-url "http://your-data-stories.eu/catalog-records/")
  :on-path "catalog-records")

(define-resource concept ()
  :class (s-prefix "skos:Concept")
  :has-many `((dataset :via ,(s-prefix "dcat:theme")
                       :inverse t
                       :as "datasets"))
  :has-one `((concept-scheme :via ,(s-prefix "skos:inScheme")
                             :as "concept-scheme"))
  :resource-base (s-url "http://your-data-stories.eu/concepts/")
  :on-path "concepts")

(define-resource concept-scheme ()
  :class (s-prefix "skos:ConceptScheme")
  :resource-base (s-url "http://your-data-stories.eu/concept-schemes/")
  :has-many `((catalog :via ,(s-prefix "dcat:themeTaxonomy")
                       :inverse t
                       :as "catalogs")
              (concept :via ,(s-prefix "skos:inScheme")
                       :inverse t
                       :as "concepts"))
  :on-path "concept-schemes")

(define-resource agent ()
  :class (s-prefix "foaf:Agent")
  :has-many `((catalog :via ,(s-prefix "dct:publisher")
                       :inverse t
                       :as "catalogs")
              (dataset :via ,(s-prefix "dct:publisher")
                       :inverse t
                       :as "datasets"))
  :resource-base (s-url "http://your-data-stories.eu/agents/")
  :on-path "agents")

(define-resource format ()
  :class (s-prefix "dct:MediaTypeOrExtent")
  :properties `((:name :string ,(s-prefix "rdfs:label"))
                (:labels :language-string-set ,(s-prefix "dct:description")))
  :has-many `((distributions :via ,(s-prefix "dct:format")
                             :inverse t
                             :as "distributions"))
  :on-path "formats"
  :resource-base (s-url "http://example.com/formats"))

(define-resource page ()
  :class (s-url "http://mu.semte.ch/vocabulary/cms/Page")
  :resource-base (s-url "http://mu.semte.ch/cms/resources/pages/")
  :properties `((:title :string ,(s-prefix "dcterms:title"))
                (:content :string ,(s-prefix "cms:pageContent")))
  :on-path "pages")

;; (around (:show page) (&rest args)
;;   (break "This is page showing with ~A" args)
;;   (let ((response (yield)))
;;     (break "The response should be ~A" (jsown:to-json response))
;;     (jsown:new-js ("ok" t))))
