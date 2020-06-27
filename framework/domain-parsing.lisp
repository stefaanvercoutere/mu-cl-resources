(in-package :mu-cl-resources)

(defun read-domain-file (relative-path)
  "Reads the JSON file from a relative path."
  (let ((type (pathname-type relative-path))
        (pathname (asdf:system-relative-pathname
                   :mu-cl-resources
                   (s+ "configuration/" relative-path))))
    (cond ((or (string= type "js")
              (string= type "json"))
           (read-domain-json-file-from-path pathname))
          ((string= type "lisp")
           (load pathname)))))

(defun read-domain-json-file-from-path (file)
  "Imports contents from the json file specified by
   file."
  (funcall (alexandria:compose
            #'read-domain-json-string
            #'alexandria:read-file-into-string)
           file))

(defun read-domain-json-string (string)
  "Imports the json string as a domain file"
  (funcall (alexandria:compose
            #'import-domain-from-jsown
            #'jsown:parse)
           string))

(defun import-prefixes-from-jsown (jsown-prefixes)
  "Imports the domain from the jsown file"
  (let ((version (jsown:val jsown-prefixes "version")))
    (cond
      ((string= version "0.1")
       (if (jsown:keyp jsown-prefixes "prefixes")
           (map-jsown-object
            (jsown:val jsown-prefixes "prefixes")
            (lambda (key value)
              (add-prefix key value)))
           (warn "Did not find \"prefixes\" key in json domain file")))
      (t (warn "Don't know version ~A for prefixes definition, skipping."
               version)))))

(defun import-domain-from-jsown (js-domain)
  "Imports the domain from the jsown file"
  (let ((version (jsown:val js-domain "version")))
    (cond
      ((string= version "0.1")
       (map-jsown-object (jsown:val js-domain "resources")
                         #'import-jsown-domain-resource))
      (t (warn "Don't know version ~A for resources definition, skipping."
               version)))))

(defun import-jsown-domain-resource (resource-name resource-description)
  (let ((properties (jsown:val-safe resource-description "properties"))
        (has-one-relationships
         (remove-if-not #'identity
                        (map-jsown-object
                         (jsown:val-safe resource-description "relationships")
                         #'maybe-import-jsown-has-one-relationship)))
        (has-many-relationships
         (remove-if-not #'identity
                        (map-jsown-object
                         (jsown:val-safe resource-description "relationships")
                         #'maybe-import-jsown-has-many-relationship)))
        (path (jsown:val resource-description "path"))
        (class (jsown:val resource-description "class"))
        (resource-base (jsown:val resource-description "newResourceBase"))
        (features (mapcar (lambda (feature)
                            (intern (string-upcase feature)))
                          (jsown:val-safe resource-description "features"))))
    (define-resource* (intern (string-upcase resource-name) :mu-cl-resources)
        :ld-class (read-uri-from-json class)
        :ld-properties (map-jsown-object properties
                                         #'import-jsown-domain-property)
        :has-many has-many-relationships
        :has-one has-one-relationships
        :ld-resource-base resource-base
        :on-path path
        :features features)))

(defun read-uri-from-json (value)
  "Reads a URI as specified in the JSON format.  Value
   is the parsed jsown variant, hence it can be either
   a string or a jsown object with keys \"type\" and
   \"value\"."
  (if (stringp value)
      (parse-simple-uri-reference value)
      (cond ((string= (jsown:val-safe value "type") "prefix")
             (s-prefix value))
            ((string= (jsown:val-safe value "type") "url")
             (s-url value))
            (t (error "Type of uri reference should be \"prefix\" or \"url\" but got \"~A\" instead."
                      (jsown:val-safe value "type"))))))

(defun parse-simple-uri-reference (value)
  "Parses a simple uri reference.  This allows you to type
   something with :// in it which will be assumed to be a
   URL, and something without to be assumed to be a prefix."
  (if (search "://" value)
      (s-url value)
      (s-prefix value)))

(defun maybe-import-jsown-has-one-relationship (relationship-path jsown-relationship)
  (when (string= "one" (string-downcase (jsown:val jsown-relationship "cardinality")))
    (list
     (intern (string-upcase (jsown:val jsown-relationship "resource")))
     :via (read-uri-from-json (jsown:val jsown-relationship "predicate"))
     :inverse (jsown:val-safe jsown-relationship "inverse")
     :as relationship-path)))

(defun maybe-import-jsown-has-many-relationship (relationship-path jsown-relationship)
  (when (string= "many" (string-downcase (jsown:val jsown-relationship "cardinality")))
    (list
     (intern (string-upcase (jsown:val jsown-relationship "resource")))
     :via (read-uri-from-json (jsown:val jsown-relationship "predicate"))
     :inverse (jsown:val-safe jsown-relationship "inverse")
     :as relationship-path)))

(defun import-jsown-domain-property (property-path jsown-property)
  "Imports a single domain property from the jsown format."
  (list
   (intern (string-upcase property-path) :keyword)
   (intern (string-upcase (jsown:val jsown-property "type")) :keyword)
   (parse-simple-uri-reference (jsown:val jsown-property "predicate"))))

;;; helpers

(defun map-jsown-object (object functor)
  "Maps the jsown object by looping over each of the keys, and
   calling functor with the key and the contents of the key as
   its arguments."
  (loop for key in (jsown:keywords object)
        for value = (jsown:val object key)
        collect (funcall functor key value)))
