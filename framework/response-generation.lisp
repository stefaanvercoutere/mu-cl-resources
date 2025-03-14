(in-package :mu-cl-resources)


(defun slot-definition-type (slot)
  "Returns the data type of the given SLOT, specifically for instances of resource-slot.
   Defaults to :string if the type is not found or slot is not a resource-slot."
  (if (typep slot 'resource-slot)
      (let ((datatype (ignore-errors (resource-type slot)))) ; Safely retrieve resource-type
        (or datatype :string)) ; Default to :string if resource-type is nil
      :string))  ; Default for non-resource-slot objects


(defun convert-to-literal (slot value)
  "Converts VALUE into a SPARQL literal with appropriate XSD type based on SLOT's data type."
  (let ((datatype (slot-definition-type slot)))
    (format t "~%[DEBUG] Converting value to literal. Slot type: ~A, Value: ~A~%" datatype value)
    (let ((literal (format-sparql-literal value datatype)))
      (format t "[DEBUG] Generated SPARQL literal: ~A~%" literal)
      literal)))

; to-do fix xsd:secure-double (should be xsd-secure:double but not wanting to update it mu-cl-resources as well for the time being)
(defun prefixed-datatype-string (datatype)
  "Returns the prefixed datatype string for DATATYPE, or NIL if not found."
  (cdr (assoc datatype
              '((:string            . "xsd:string")
                (:integer           . "xsd:integer")
                (:boolean           . "xsd:boolean")
                (:datetime          . "xsd:dateTime")
                (:time              . "xsd:time")
                (:date              . "xsd:date")
                (:g-year            . "xsd:gYear")
                (:geometry          . "geo:wktLiteral")
                (:float             . "xsd:float")
                (:number            . "xsd:decimal")
                (:double            . "xsd:double")
                (:xsd-secure-double . "xsd-secure:double")
                (:rdfs-string       . "rdfs:string")
                (:rdfs-integer      . "rdfs:integer"))
              :test #'eq)))

(defun format-sparql-literal (value datatype &optional lang)
  "Formats VALUE as a SPARQL literal using a prefixed datatype if available.
For :language-string, appends the language tag (defaulting to \"nl\").
For known XSD/RDFS types, uses the appropriate prefix without angle brackets.
For unknown types, returns an untyped literal."
  (let* ((formatted-value (format-value-for-datatype value datatype))
         (prefixed (prefixed-datatype-string datatype)))
    (cond
      ((eq datatype :language-string)
       (format nil "\"\"\"~A\"\"\"@~A" formatted-value (or lang "nl")))
      (prefixed
       (format nil "\"\"\"~A\"\"\"^^~A" formatted-value prefixed))
      (t
       (format nil "\"\"\"~A\"\"\"" formatted-value)))))

(defun format-value-for-datatype (value datatype)
  "Formats VALUE based on DATATYPE requirements."
  (case datatype
    (:boolean (string-downcase value))
    (otherwise value)))

(defun cache-clear-json-path (resource json-path)
  "Clears any cached entries associated with the given JSON path on RESOURCE.
JSON-PATH is the portion of the resource's JSON structure for which the cache should be invalidated.
This is a stub implementation—replace it with your actual cache clearing logic."
  (declare (ignore resource json-path))
  ;; Implement your cache invalidation here.
  nil)

(defun try-parse-number (entity)
  "Tries to parse the number, returns nil if no number could be found."
  (handler-case
      (parse-integer entity :junk-allowed t)
    (error () nil)))

(defun cache-count-queries-p (resource)
  "Returns a truethy value iff the count queries should be cached for
   resource."
  (or *cache-count-queries-p*
     (find 'cache-count-queries (features resource))))

(defun count-matches (identifier-variable query-body resource link-spec)
  "Returns the amount of matches for a particular response."
  (flet ((sparql-count ()
           (parse-integer
            (jsown:filter (first (sparql:select (format nil "((COUNT (DISTINCT ~A)) AS ?count)"
                                                        identifier-variable)
                                                query-body))
                          "count" "value"))))
    (if (cache-count-queries-p resource)
        (or (count-cache resource link-spec)
           (setf (count-cache resource link-spec) (sparql-count)))
        (sparql-count))))

(defun extract-pagination-info-from-request ()
  "Extracts the pagination info from the current request object.
   The first value is a list containing the page size and page
   number.
   The second value indicates whether the page size and page
   number supplied by the end-user."
  (let ((page-size (or (try-parse-number (webserver:get-parameter "page[size]")) *default-page-size*))
        (page-number (or (try-parse-number (webserver:get-parameter "page[number]")) 0)))
    (values (list page-size page-number)
            (list (and (webserver:get-parameter "page[size]") t)
                  (and (webserver:get-parameter "page[number]") t)))))

(let ((destructuring-search-term-scanner (cl-ppcre:create-scanner "(-)?(:.*:)?([^:]+)")))
  (defun extract-order-info-from-request (resource)
    "Extracts the order info from the current request object."
    (alexandria:when-let ((sort (webserver:get-parameter "sort")))
      (loop for sort-string in (cl-ppcre:split "," sort)
            for term-portions = (multiple-value-bind (match portions)
                                    (cl-ppcre:scan-to-strings destructuring-search-term-scanner sort-string)
                                  (declare (ignore match))
                                  portions)
            for descending-p = (not (null (aref term-portions 0)))
            for modifiers = (when (and (aref term-portions 1) (string= (aref term-portions 1) ":no-case:"))
                              (list :no-case))
            for attribute-name = (aref term-portions 2)
            for components = (split-sequence:split-sequence #\. attribute-name)
            collect (list :order (if descending-p :descending :ascending)
                          :name attribute-name
                          :property-path (property-path-for-filter-components resource components nil)
                          :modifiers modifiers)))))

(defun paginate-uuids-for-sparql-body (&key sparql-body page-size page-number order-info source-variable)
  "Returns the paginated uuids for the supplied sparql body and
   side constraints."
  (let ((order-variables (loop for info in order-info
                            for name = (getf info :name)
                            collect
                              (s-genvar name))))
    ;; looking at the implementation, much of it is split
    ;; between having to sort (order-info) and not having
    ;; to sort.  some logic is shared.
    (let ((sparql-variables (cond
                              ((and order-info *max-group-sorted-properties*)
                               (format nil "DISTINCT ~A~{ ~{(MAX(~A) AS ~A)~}~}"
                                       (s-var "uuid") (mapcar (lambda (a) (list a (s-genvar "tmp"))) order-variables)))
                              ((and order-info (not *max-group-sorted-properties*))
                               (format nil "DISTINCT ~A~{ ~A~}"
                                       (s-var "uuid") order-variables))
                              (t
                               (format nil "DISTINCT ~A" (s-var "uuid")))))
          (sparql-body (if order-info
                           (format nil "~A~%~{OPTIONAL {~{~A ~{~A~^/~} ~A~}.}~%~}"
                                   sparql-body
                                   (loop for info in order-info
                                      for variable in order-variables
                                      collect
                                        (list source-variable (getf info :property-path) variable)))
                           sparql-body))
          (order-by (if order-info
                        (format nil "~{~A(~A) ~}"
                                (loop for info in order-info
                                      for variable in order-variables
                                      append (list
                                              (if (eq (getf info :order)
                                                      :ascending)
                                                  "ASC" "DESC")
                                              (let ((var (if (find :no-case (getf info :modifiers) :test #'eq)
                                                             (format nil "LCASE(STR(~A))" variable)
                                                             variable)))
                                                (if *max-group-sorted-properties*
                                                    (format nil "MAX(~A)" var)
                                                    var)))))))
          (group-by (s-var "uuid"))
          (limit page-size)
          (offset (if (and page-size page-number) (* page-size page-number) 0)))
      (jsown:filter (sparql:select sparql-variables sparql-body
                                   :order-by order-by
                                   :group-by group-by
                                   :limit limit
                                   :offset offset)
                    map "uuid" "value"))))

(defun build-pagination-links (base-path &key page-number page-size total-count)
  "Builds a links object containing the necessary pagination
   links.  It bases itself on the base-path for the targeted
   request."
  (flet ((build-url (&key page-number)
           (let ((get-parameters (alist-to-plist (webserver:get-parameters*))))
             (setf (getfstr get-parameters "page[number]")
                   (and (> page-number 0) page-number))
             (setf (getfstr get-parameters "page[size]")
                   (and (/= page-size *default-page-size*)
                        page-size))
             (build-url base-path get-parameters))))
    (let ((last-page (max 0 (1- (ceiling (/ total-count page-size))))))
      (let ((links (jsown:new-js
                     ("first" (build-url :page-number 0))
                     ("last" (build-url :page-number last-page)))))
        (unless (<= page-number 0)
          (setf (jsown:val links "prev")
                (build-url :page-number (1- page-number))))
        (unless (>= page-number last-page)
          (setf (jsown:val links "next")
                (build-url :page-number (1+ page-number))))
        links))))

(defun include-count-feature-p (resource)
  "returns non-nil if the count of  available items should be
   included in meta response of paginated collections"
  (or *include-count-in-paginated-responses*
     (find 'include-count (features resource))))

(defun paginated-collection-response (&key resource sparql-body link-spec link-defaults source-variable self)
  "Constructs the paginated response for a collection listing."
  (destructuring-bind ((page-size page-number) (page-size-p page-number-p))
      (multiple-value-list (extract-pagination-info-from-request))
    (let ((order-info (extract-order-info-from-request resource))
          (use-pagination (or page-size-p page-number-p
                              (not (find 'no-pagination-defaults
                                       (features resource))))))
      (let ((uuid-count (count-matches (s-var "uuid") sparql-body resource link-spec))
            (uuids (paginate-uuids-for-sparql-body :sparql-body sparql-body
                                                   :page-size (and use-pagination page-size)
                                                   :page-number (and use-pagination page-number)
                                                   :source-variable source-variable
                                                   :order-info order-info))
            (resource-type (resource-name resource)))
        (multiple-value-bind (data-item-specs included-item-specs)
            (augment-data-with-attached-info (mapcar (lambda (uuid)
                                                       ;; TODO: resource-type should be calculated, may need to be a sub class?
                                                       (make-item-spec :uuid uuid :type resource-type))
                                                     uuids)
                                             resource)
          (let ((response
                  (jsown:new-js ("data" (item-specs-to-jsown data-item-specs))
                    ("links" (merge-jsown-objects
                              (build-pagination-links (webserver:script-name*)
                                                      :total-count uuid-count
                                                      :page-size page-size
                                                      :page-number page-number)
                              link-defaults)))))
            (when self
              (setf (jsown:val (jsown:val response "links") "self") self))
            (when (include-count-feature-p resource)
              (setf (jsown:val response "meta")
                    (jsown:new-js ("count" uuid-count))))
            (when included-item-specs
              (setf (jsown:val response "included")
                    (item-specs-to-jsown included-item-specs)))
            (values response data-item-specs included-item-specs)))))))

(defun cache-clear-relation-json-path (resource json-relations)
  "Creates clear keys for the relation as followed through relationships specified by json keys."
  (loop for (resource . link)
          in (resource-link-combinations-for-json-path resource json-relations)
        do (cache-relation resource link)))

(defun resource-link-combinations-for-json-path (resource json-relations)
  "Collects source resource and link combinations for the source resource and json relations. 
  Yields the last target resource as second value."
  (let ((current-resource resource)
        resource-link-list)
    (dolist (json-relation json-relations)
      (let ((link (find-resource-link-by-json-key current-resource json-relation)))
        (push (cons current-resource link) resource-link-list)
        (setf current-resource (referred-resource link))))
    (values (reverse resource-link-list) current-resource)))

(defun sparql-pattern-filter-string (resource source-variable &key components search)
  "Constructs the SPARQL pattern for a filter constraint.
  RESOURCE is the current resource definition, SOURCE-VARIABLE is the SPARQL variable from which
  filtering begins, COMPONENTS is the list of filter path components, and SEARCH is the search string."
  (let ((search-var (s-genvar "search"))
        (last-component (car (last components))))
    (labels ((smart-filter-p (pattern)
               "Returns non-nil if the last filter component matches the supplied PATTERN."
               (eql 0 (search pattern last-component)))
             (comparison-filter (pattern comparator)
               (cache-clear-json-path resource (butlast components))
               (let ((new-components (append (butlast components)
                                             (list (subseq last-component (length pattern))))))
                 (multiple-value-bind (pattern target-variable last-slot slots)
                     (sparql-pattern-for-filter-components source-variable resource new-components nil)
                   (declare (ignore slots))
                   (format nil "~A FILTER (~A ~A ~A)~&"
                           pattern
                           target-variable
                           comparator
                           (interpret-json-string last-slot search))))))
      (cond
        ;; Filter for IDs
        ((and (or (deprecated (:silent "Use [:id:] instead.")
                    (string= "id" last-component))
                  (string= ":id:" last-component)))
         (cache-clear-relation-json-path resource (butlast components))
         (let ((search-components (mapcar #'s-str (split-sequence:split-sequence #\, search))))
           (multiple-value-bind (sparql-pattern target-variable last-slot slots)
               (sparql-pattern-for-filter-components source-variable resource (butlast components) nil)
             (declare (ignore last-slot slots))
             (format nil "~A ~A mu:uuid ~A. VALUES ~A {~{~A~^ ~}} ~&"
                     sparql-pattern
                     target-variable search-var
                     search-var search-components))))
        ;; Filter for URIs
        ((string= ":uri:" last-component)
         (if (> (length components) 1)
             (let* ((slots (slots-for-filter-components resource (butlast components)))
                    (last-slot (first (reverse slots)))
                    (last-slot-attribute-p (typep last-slot 'resource-slot)))
               (if last-slot-attribute-p
                   (cache-clear-json-path resource (nbutlast components 2))
                   (cache-clear-relation-json-path resource (butlast components)))
               (multiple-value-bind (sparql-pattern target-variable last-slot slots)
                   (sparql-pattern-for-filter-components source-variable resource (butlast components) nil)
                 (declare (ignore last-slot slots))
                 (format nil "~A VALUES ~A { ~A } ~&"
                         sparql-pattern
                         target-variable (s-url search))))
             (format nil "VALUES ~A { ~A } ~&"
                     source-variable (s-url search))))
        ;; Exact search branch: use convert-to-literal to attach xsd:string when appropriate.
        ((smart-filter-p ":exact:")
         (cache-clear-json-path resource (butlast components))
         (let ((last-property (subseq last-component (length ":exact:"))))
           (multiple-value-bind (sparql-pattern target-variable last-slot slots)
               (sparql-pattern-for-filter-components source-variable resource (butlast components) nil)
             (declare (ignore slots))
             (let* ((last-resource (if last-slot (referred-resource last-slot) resource))
                    (property-slot (resource-slot-by-json-key last-resource last-property)))

               (format t "~%[DEBUG] :exact: case~%")
               (format t "  Last property: ~A~%" last-property)
               (format t "  Property slot: ~A~%" property-slot)

               (format nil "~A ~A ~{~A~^/~} ~A.~&"
                       sparql-pattern
                       target-variable (ld-property-list property-slot)
                       (convert-to-literal property-slot search))))))
        ;; Comparison filters
        ((smart-filter-p ":gt:") (comparison-filter ":gt:" ">"))
        ((smart-filter-p ":lt:") (comparison-filter ":lt:" "<"))
        ((smart-filter-p ":gte:") (comparison-filter ":gte:" ">="))
        ((smart-filter-p ":lte:") (comparison-filter ":lte:" "<="))
        ;; has-no filter
        ((smart-filter-p ":has-no:")
         (let ((new-components (append (butlast components)
                                       (list (subseq last-component (length ":has-no:"))))))
           (multiple-value-bind (sparql-pattern target-variable last-slot slots)
               (sparql-pattern-for-filter-components source-variable resource new-components nil)
             (declare (ignore target-variable slots))
             (if (typep last-slot 'has-link)
                 (cache-clear-relation-json-path resource new-components)
                 (cache-clear-json-path resource (butlast new-components)))
             (format nil "FILTER( NOT EXISTS {~&~T~T~A~&~T} )~&" sparql-pattern))))
        ;; has filter
        ((smart-filter-p ":has:")
         (let ((new-components (append (butlast components)
                                       (list (subseq last-component (length ":has:"))))))
           (multiple-value-bind (sparql-pattern target-variable last-slot slots)
               (sparql-pattern-for-filter-components source-variable resource new-components nil)
             (declare (ignore target-variable slots))
             (if (typep last-slot 'has-link)
                 (cache-clear-relation-json-path resource new-components)
                 (cache-clear-json-path resource (butlast new-components)))
             (format nil "FILTER( EXISTS {~&~T~T~A~&~T} )~&" sparql-pattern))))
        ;; not filter
        ((smart-filter-p ":not:")
         (let ((last-property (subseq last-component (length ":not:"))))
           (multiple-value-bind (sparql-pattern target-variable last-slot slots)
               (sparql-pattern-for-filter-components source-variable resource (butlast components) nil)
             (declare (ignore slots))
             (let* ((last-resource (if last-slot (referred-resource last-slot) resource))
                    (property-slot (resource-slot-by-json-key last-resource last-property)))
               (format nil "FILTER( NOT EXISTS { ~A ~A ~A ~A. } )"
                       sparql-pattern
                       target-variable (ld-property-list property-slot)
                       (interpret-json-string property-slot search))))))
        ;; Standard semi-fuzzy search
        (t
         (multiple-value-bind (sparql-pattern target-variable last-slot slots)
             (sparql-pattern-for-filter-components source-variable resource components t)
           (declare (ignore slots))
           (cache-clear-json-path resource
                                  (if (typep last-slot 'has-link)
                                      components
                                      (butlast components)))
           (format nil "~A FILTER CONTAINS(LCASE(str(~A)), LCASE(~A)) ~&"
                   sparql-pattern
                   target-variable (s-str search))))))))


(defun extract-filters-from-request ()
  "Extracts the filters from the request.  The result is a list
   containing the :components and :search key.  The :components
   key includes a left-to-right specification of the strings
   between brackets.  The :search contains the content for that
   specification."
  (loop for (param . value) in (webserver:get-parameters*)
     if (eql (search "filter" param :test #'char=) 0)
     collect (list :components
                   (mapcar (lambda (str)
                             (subseq str 0 (1- (length str))))
                           (rest (cl-ppcre:split "\\[" param)))
                   :search
                   value)))

 (let ((or-scanner (cl-ppcre:create-scanner "^:or:" :single-line-mode t)))
  (defun group-filters (filters)
    "Groups filters as added to the search to make sure AND and OR is
  understood correctly."
    (let ((map (make-hash-table :test 'equal)))
      (loop for filter-spec in filters
            for components = (getf filter-spec :components)
            for search = (getf filter-spec :search)
            if (cl-ppcre:scan or-scanner (first components))
              do (push (list :components (rest components) :search search) (gethash (first components) map))
            else
              do (push (list :components components :search search) (gethash ":and:" map)))
      (loop for group being the hash-keys of map
            for settings = (gethash group map)
            if (cl-ppcre:scan or-scanner group)
              collect (cons :or settings)
            else
              collect (cons :and settings)))))

(defun filter-body-for-search (&key resource source-variable sparql-body)
  "Adds constraints to sparql-body so that it abides the filters
   which were posed by the user."
  (flet ((expand-filter-string (options)
           (apply #'sparql-pattern-filter-string
                  resource source-variable
                  options)))
   (loop for (type . group-filters) in (group-filters (extract-filters-from-request))
         if (eq type :or)
           do (setf sparql-body         ; append this to the sparql body
                    (format nil "~A~%~{{~% ~A~%} ~,^ UNION ~%~}" sparql-body
                            (mapcar #'expand-filter-string group-filters)))
         else
           do
              (setf sparql-body
                    (format nil "~A~{~%~A~}" sparql-body
                            (mapcar #'expand-filter-string group-filters)))))
  sparql-body)
